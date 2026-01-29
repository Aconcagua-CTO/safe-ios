import UIKit

/// MoneyMarket (Aave) token details.
/// Shows supply APY chart for the selected interval, current APY, and total supplied (USD).
final class MoneyMarketTokenDetailViewController: UIViewController {
    private let token: TokenBalance
    private weak var balancesProvider: TokenDetailBalancesProvider?

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let headerView = TokenPriceHistoryHeaderView()

    private let aaveClient = AaveV3GraphQLClient()
    private let yieldService = MoneyMarketYieldService()
    private let ondoUSDYClient = OndoUSDYPageClient()

    private var reserveTask: URLSessionDataTask?
    private var historyTask: URLSessionDataTask?
    private var ondoUSDYTask: URLSessionDataTask?

    private enum HistoryMode {
        case aaveYield
        case ondoYield
        case ondoPrice
    }

    private enum Row: Int, CaseIterable {
        case network
        case apy
        case totalSuppliedUsd
    }

    private var selectedChainId: Int?
    private var selectedATokenAddress: String?
    private var selectedMarketPoolAddress: String?
    private var selectedUnderlyingTokenAddress: String?
    private var selectionReason: String?
    private var selectedHistoryMode: HistoryMode?

    private var apyText: String = "—"
    private var totalSuppliedUsdText: String = "—"
    private var selectedInterval: TokenPriceHistoryHeaderView.Interval = .week

    init(token: TokenBalance, balancesProvider: TokenDetailBalancesProvider?) {
        self.token = token
        self.balancesProvider = balancesProvider
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        reserveTask?.cancel()
        historyTask?.cancel()
        ondoUSDYTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .backgroundPrimary
        title = token.symbol

        configureTable()
        configureHeader()
        reloadData()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if tableView.tableHeaderView === headerView {
            let targetHeight: CGFloat = 260
            if headerView.frame.width != tableView.bounds.width || headerView.frame.height != targetHeight {
                headerView.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: targetHeight)
                tableView.tableHeaderView = headerView
            }
        }
    }

    private func configureTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .backgroundPrimary
        tableView.dataSource = self
        tableView.delegate = self

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureHeader() {
        let fallbackWidth = max(view.bounds.width, UIScreen.main.bounds.width)
        headerView.frame = CGRect(x: 0, y: 0, width: fallbackWidth, height: 260)
        tableView.tableHeaderView = headerView
        headerView.onIntervalChanged = { [weak self] interval in
            self?.selectedInterval = interval
            self?.fetchHistoryIfPossible()
        }
        headerView.setSelectedInterval(selectedInterval)
        headerView.showPlaceholder(text: NSLocalizedString("ui_chart_loading_yield", comment: "Loading yield chart"))
    }

    private func reloadData() {
        reserveTask?.cancel()
        historyTask?.cancel()
        ondoUSDYTask?.cancel()
        reserveTask = nil
        historyTask = nil
        ondoUSDYTask = nil

        headerView.showLoading()
        apyText = "—"
        totalSuppliedUsdText = "—"
        selectionReason = nil
        selectedChainId = nil
        selectedATokenAddress = nil
        selectedMarketPoolAddress = nil
        selectedUnderlyingTokenAddress = nil
        selectedHistoryMode = nil
        tableView.reloadData()

        let holdings = balancesProvider?.moneyMarketHoldings(for: token) ?? []
        guard !holdings.isEmpty else {
            headerView.showPlaceholder(text: NSLocalizedString("ui_chart_no_moneymarket_holdings", comment: "No MoneyMarket holdings"))
            tableView.reloadData()
            return
        }

        if holdings.count == 1 {
            selectionReason = "single network"
            selectHolding(holdings[0])
            return
        }

        if hasOndoUSDYSources(holdings) {
            selectionReason = "first network"
            selectHolding(holdings[0])
            return
        }

        // Multiple chains: pick the one with highest current APY.
        selectionReason = "highest APY"
        let keys = holdings.map { MoneyMarketYieldService.QueryKey(chainId: $0.chainId, aTokenAddressLowercased: $0.aTokenAddress.lowercased()) }
        yieldService.fetchApyPercents(keys: keys) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                // Fallback: pick first holding.
                self.selectHolding(holdings[0])
            case .success(let map):
                let best = holdings.max { a, b in
                    let apyA = map[a.aTokenAddress.lowercased()] ?? -Double.greatestFiniteMagnitude
                    let apyB = map[b.aTokenAddress.lowercased()] ?? -Double.greatestFiniteMagnitude
                    return apyA < apyB
                } ?? holdings[0]
                self.selectHolding(best)
            }
        }
    }

    private func selectHolding(_ holding: (chainId: Int, aTokenAddress: String)) {
        selectedChainId = holding.chainId
        selectedATokenAddress = holding.aTokenAddress

        guard let meta = balancesProvider?.tokenMetadata(chainId: holding.chainId, tokenAddress: holding.aTokenAddress) else {
            headerView.showPlaceholder(text: NSLocalizedString("ui_chart_yield_unavailable_missing_whitelist", comment: "Yield data unavailable (missing whitelist entry)"))
            tableView.reloadData()
            return
        }
        let yieldSource = (meta.yieldSource ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let priceSource = (meta.priceSource ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let market = (meta.aaveMarketPoolAddress ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let underlying = (meta.aaveUnderlyingTokenAddress ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if yieldSource == "aave_v3", !market.isEmpty, !underlying.isEmpty {
            selectedHistoryMode = .aaveYield
            selectedMarketPoolAddress = market
            selectedUnderlyingTokenAddress = underlying
            tableView.reloadData()

            // Fetch snapshot + history.
            headerView.showLoading()

            reserveTask = aaveClient.fetchReserveSnapshot(
                chainId: holding.chainId,
                marketPoolAddress: market,
                underlyingTokenAddress: underlying
            ) { [weak self] result in
                guard let self else { return }
                switch result {
                case .failure:
                    self.apyText = "—"
                    self.totalSuppliedUsdText = "—"
                case .success(let snap):
                    self.apyText = Self.formatPercent(snap.supplyApyPercent)
                    self.totalSuppliedUsdText = Self.formatCompactUsd(snap.totalSuppliedUsd)
                }
                self.tableView.reloadData()
            }

            fetchHistoryIfPossible()
            return
        }

        if yieldSource == "ondousdy" {
            selectedHistoryMode = .ondoYield
            selectedMarketPoolAddress = nil
            selectedUnderlyingTokenAddress = nil
            totalSuppliedUsdText = "—"
            tableView.reloadData()
            fetchHistoryIfPossible()
            return
        }

        if priceSource == "ondousdy" {
            selectedHistoryMode = .ondoPrice
            selectedMarketPoolAddress = nil
            selectedUnderlyingTokenAddress = nil
            totalSuppliedUsdText = "—"
            tableView.reloadData()
            fetchHistoryIfPossible()
            return
        }

        headerView.showPlaceholder(text: NSLocalizedString("ui_chart_yield_unavailable_not_enriched", comment: "Yield data unavailable (not enriched)"))
        tableView.reloadData()
    }

    private func fetchHistoryIfPossible() {
        guard let mode = selectedHistoryMode else { return }
        switch mode {
        case .aaveYield:
            guard let chainId = selectedChainId,
                  let market = selectedMarketPoolAddress,
                  let underlying = selectedUnderlyingTokenAddress else {
                return
            }
            historyTask?.cancel()
            historyTask = nil
            headerView.showLoading()

            historyTask = aaveClient.fetchSupplyApyHistory(
                chainId: chainId,
                marketPoolAddress: market,
                underlyingTokenAddress: underlying,
                window: aaveWindow(for: selectedInterval)
            ) { [weak self] result in
                guard let self else { return }
                switch result {
                case .failure:
                    self.headerView.showPlaceholder(text: NSLocalizedString("ui_chart_yield_unavailable", comment: "Yield chart unavailable"))
                case .success(let points):
                    let chartPoints = points.map { TokenPriceHistoryHeaderView.Point(time: $0.time, value: $0.apyPercent) }
                    if chartPoints.count >= 2 {
                        self.headerView.showChart(points: chartPoints)
                    } else {
                        self.headerView.showPlaceholder(text: NSLocalizedString("ui_chart_yield_unavailable", comment: "Yield chart unavailable"))
                    }
                }
            }
        case .ondoYield:
            fetchOndoUSDYHistory(mode: .yield)
        case .ondoPrice:
            fetchOndoUSDYHistory(mode: .price)
        }
    }

    private enum OndoUSDYMode {
        case price
        case yield
    }

    private func fetchOndoUSDYHistory(mode: OndoUSDYMode) {
        ondoUSDYTask?.cancel()
        ondoUSDYTask = nil
        headerView.showLoading()

        ondoUSDYTask = ondoUSDYClient.fetchSnapshot { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                let placeholderKey = (mode == .yield)
                    ? "ui_chart_yield_unavailable"
                    : "ui_chart_coming_soon"
                self.headerView.showPlaceholder(text: NSLocalizedString(placeholderKey, comment: "Chart unavailable"))
            case .success(let snapshot):
                let filtered = self.filterHistory(snapshot.history, for: self.selectedInterval)
                let points = filtered.map { point in
                    let value = (mode == .yield) ? point.apyPercent : point.priceUsd
                    return TokenPriceHistoryHeaderView.Point(time: point.time, value: value)
                }

                if let last = filtered.last {
                    self.apyText = Self.formatPercent(last.apyPercent)
                } else {
                    self.apyText = "—"
                }
                self.totalSuppliedUsdText = "—"
                self.tableView.reloadData()

                if points.count >= 2 {
                    self.headerView.showChart(points: points)
                } else {
                    let placeholderKey = (mode == .yield)
                        ? "ui_chart_yield_unavailable"
                        : "ui_chart_coming_soon"
                    self.headerView.showPlaceholder(text: NSLocalizedString(placeholderKey, comment: "Chart unavailable"))
                }
            }
        }
    }

    private func filterHistory(_ history: [OndoUSDYPageClient.HistoryPoint],
                               for interval: TokenPriceHistoryHeaderView.Interval) -> [OndoUSDYPageClient.HistoryPoint] {
        let secondsBack: TimeInterval = {
            switch interval {
            case .week:
                return 7 * 24 * 60 * 60
            case .month:
                return 30 * 24 * 60 * 60
            case .year:
                return 365 * 24 * 60 * 60
            }
        }()
        let cutoff = Date().timeIntervalSince1970 - secondsBack
        return history.filter { $0.time >= cutoff }
    }

    private func hasOndoUSDYSources(_ holdings: [(chainId: Int, aTokenAddress: String)]) -> Bool {
        for holding in holdings {
            guard let meta = balancesProvider?.tokenMetadata(chainId: holding.chainId, tokenAddress: holding.aTokenAddress) else {
                continue
            }
            let yieldSource = (meta.yieldSource ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let priceSource = (meta.priceSource ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if yieldSource == "ondousdy" || priceSource == "ondousdy" {
                return true
            }
        }
        return false
    }

    private func aaveWindow(for interval: TokenPriceHistoryHeaderView.Interval) -> AaveV3GraphQLClient.TimeWindow {
        switch interval {
        case .week:
            return .lastWeek
        case .month:
            return .lastMonth
        case .year:
            return .lastYear
        }
    }

    private static func chainDisplayName(chainId: Int) -> String {
        if let chain = Chain.by(String(chainId)) {
            return chain.name ?? "Chain \(chainId)"
        }
        return "Chain \(chainId)"
    }

    private static func formatPercent(_ percent: Double) -> String {
        guard percent > 0 else { return "0.00%" }
        if percent > 0, percent < 0.01 { return "<0.01%" }
        return String(format: "%.2f%%", percent)
    }

    private static func formatCompactUsd(_ usd: Double) -> String {
        let absV = abs(usd)
        let (scaled, suffix): (Double, String) = {
            if absV >= 1_000_000_000 { return (usd / 1_000_000_000, "B") }
            if absV >= 1_000_000 { return (usd / 1_000_000, "M") }
            if absV >= 1_000 { return (usd / 1_000, "K") }
            return (usd, "")
        }()
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale.autoupdatingCurrent
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        let s = f.string(from: NSNumber(value: scaled)) ?? "\(scaled)"
        return "$" + s + suffix
    }
}

extension MoneyMarketTokenDetailViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Row.allCases.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.selectionStyle = .none

        let row = Row(rawValue: indexPath.row)!
        switch row {
        case .network:
            cell.textLabel?.text = "Network"
            if let chainId = selectedChainId {
                let name = Self.chainDisplayName(chainId: chainId)
                if let reason = selectionReason {
                    cell.detailTextLabel?.text = "\(name) (\(reason))"
                } else {
                    cell.detailTextLabel?.text = name
                }
            } else {
                cell.detailTextLabel?.text = "—"
            }
        case .apy:
            cell.textLabel?.text = "Current APY"
            cell.detailTextLabel?.text = apyText
        case .totalSuppliedUsd:
            cell.textLabel?.text = "Total supplied"
            cell.detailTextLabel?.text = totalSuppliedUsdText
        }

        return cell
    }
}


