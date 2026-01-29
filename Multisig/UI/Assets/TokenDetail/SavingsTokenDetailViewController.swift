import UIKit

final class SavingsTokenDetailViewController: UIViewController {
    private let token: TokenBalance
    private weak var balancesProvider: TokenDetailBalancesProvider?

    private let tableView = UITableView(frame: .zero, style: .plain)
    private var rows: [NetworkTokenBalanceRow] = []

    private let invertirButton = UIButton(type: .system)
    private var invertirFlowCoordinator: InvertirFromTokenDetailFlowCoordinator?

    private let priceHeaderView = TokenPriceHistoryHeaderView()
    private let priceHistoryService = KrakenPriceHistoryService()
    private var ohlcTask: URLSessionDataTask?
    private let aaveClient = AaveV3GraphQLClient()
    private var aaveHistoryTask: URLSessionDataTask?
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
        ohlcTask?.cancel()
        aaveHistoryTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .backgroundPrimary
        title = token.symbol

        configureTable()
        configureInvertirButton()
        configurePriceHistoryHeader()
        reloadRows()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // tableHeaderView uses frames (not Auto Layout). Keep it sized to current width.
        if tableView.tableHeaderView === priceHeaderView {
            let targetHeight: CGFloat = 260
            if priceHeaderView.frame.width != tableView.bounds.width || priceHeaderView.frame.height != targetHeight {
                priceHeaderView.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: targetHeight)
                tableView.tableHeaderView = priceHeaderView
            }
        }
    }

    private func configureTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .backgroundPrimary
        tableView.separatorColor = .separator
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }

        tableView.register(SavingsNetworkBalanceCell.self, forCellReuseIdentifier: SavingsNetworkBalanceCell.reuseIdentifier)
        tableView.dataSource = self
        tableView.delegate = self

        view.addSubview(tableView)
        view.addSubview(invertirButton)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: invertirButton.topAnchor, constant: -12),

            invertirButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            invertirButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            invertirButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            invertirButton.heightAnchor.constraint(equalToConstant: 56)
        ])
    }

    private func configureInvertirButton() {
        invertirButton.translatesAutoresizingMaskIntoConstraints = false
        invertirButton.setText(NSLocalizedString("ui_invertir_progress_title", comment: "Invertir button title"), .filled)
        invertirButton.addTarget(self, action: #selector(didTapInvertir), for: .touchUpInside)
    }

    @objc private func didTapInvertir() {
        guard let nav = navigationController else { return }
        let flow = InvertirFromTokenDetailFlowCoordinator(navigationController: nav, token: token)
        flow.onFinish = { [weak self] in
            self?.invertirFlowCoordinator = nil
        }
        invertirFlowCoordinator = flow
        flow.start()
    }

    private func configurePriceHistoryHeader() {
        // Always show a header. For non-Kraken tokens it will display "Chart coming soon".
        let fallbackWidth = max(view.bounds.width, UIScreen.main.bounds.width)
        priceHeaderView.frame = CGRect(x: 0, y: 0, width: fallbackWidth, height: 260)
        tableView.tableHeaderView = priceHeaderView
        priceHeaderView.onIntervalChanged = { [weak self] interval in
            self?.selectedInterval = interval
            self?.fetchPriceHistory(interval: interval)
        }
        priceHeaderView.setSelectedInterval(selectedInterval)
        fetchPriceHistory(interval: selectedInterval)
    }

    private func fetchPriceHistory(interval: TokenPriceHistoryHeaderView.Interval) {
        ohlcTask?.cancel()
        ohlcTask = nil
        aaveHistoryTask?.cancel()
        aaveHistoryTask = nil

        let normalizedCategory = token.category
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        let tokenSymbolUpper = token.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if isSavingsYieldCategory(normalizedCategory) {
            let source = (token.yieldSource ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let market = (token.aaveMarketPoolAddress ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let underlying = (token.aaveUnderlyingTokenAddress ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard source == "aave_v3", !market.isEmpty, !underlying.isEmpty else {
                #if DEBUG
                LogService.shared.debug(
                    "[Savings][YieldChart] token=\(tokenSymbolUpper) yieldSource=\(source) config=missing"
                )
                #endif
                priceHeaderView.showPlaceholder(text: NSLocalizedString("ui_chart_yield_unavailable", comment: "Yield chart unavailable"))
                return
            }

            let chainId = Int(token.yieldChainId ?? "") ?? 1

            #if DEBUG
            LogService.shared.debug(
                "[Savings][YieldChart] token=\(tokenSymbolUpper) chainId=\(chainId) market=\(market) underlying=\(underlying) interval=\(interval)"
            )
            #endif

            priceHeaderView.showLoading()
            aaveHistoryTask = aaveClient.fetchSupplyApyHistory(
                chainId: chainId,
                marketPoolAddress: market,
                underlyingTokenAddress: underlying,
                window: aaveWindow(for: interval)
            ) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let points):
                    let chartPoints = points.map { TokenPriceHistoryHeaderView.Point(time: $0.time, value: $0.apyPercent) }
                    if chartPoints.count >= 2 {
                        self.priceHeaderView.showChart(points: chartPoints)
                    } else {
                        self.priceHeaderView.showPlaceholder(text: NSLocalizedString("ui_chart_yield_unavailable", comment: "Yield chart unavailable"))
                    }
                case .failure:
                    self.priceHeaderView.showPlaceholder(text: NSLocalizedString("ui_chart_yield_unavailable", comment: "Yield chart unavailable"))
                }
            }
            return
        }

        guard let pair = balancesProvider?.krakenPair(for: token) else {
            priceHeaderView.showPlaceholder(text: NSLocalizedString("ui_chart_coming_soon", comment: "Chart placeholder"))
            return
        }

        #if DEBUG
        LogService.shared.debug(
            "[Savings][PriceChart] token=\(tokenSymbolUpper) category=\(normalizedCategory) pair=\(pair) interval=\(interval)"
        )
        #endif

        priceHeaderView.showLoading()
        ohlcTask = priceHistoryService.fetchClosePoints(pair: pair, window: krakenWindow(for: interval)) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let servicePoints):
                    let points = servicePoints.map { TokenPriceHistoryHeaderView.Point(time: $0.time, value: $0.close) }
                    if points.count >= 2 {
                        self.priceHeaderView.showChart(points: points)
                    } else {
                        self.priceHeaderView.showPlaceholder(text: NSLocalizedString("ui_chart_coming_soon", comment: "Chart placeholder"))
                    }
                case .failure:
                    self.priceHeaderView.showPlaceholder(text: NSLocalizedString("ui_chart_coming_soon", comment: "Chart placeholder"))
                }
            }
        }
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

    private func isSavingsYieldCategory(_ normalizedCategory: String) -> Bool {
        TokenCategory.isSavings(normalizedCategory)
    }

    private func krakenWindow(for interval: TokenPriceHistoryHeaderView.Interval) -> KrakenPriceHistoryService.TimeWindow {
        switch interval {
        case .week:
            return .week
        case .month:
            return .month
        case .year:
            return .year
        }
    }

    private func reloadRows() {
        rows = balancesProvider?.savingsBreakdownRows(for: token) ?? []
        tableView.reloadData()
    }
}

extension SavingsTokenDetailViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = rows[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: SavingsNetworkBalanceCell.reuseIdentifier, for: indexPath) as! SavingsNetworkBalanceCell
        cell.configure(row: row)
        return cell
    }
}

final class SavingsNetworkBalanceCell: UITableViewCell {
    static let reuseIdentifier = "SavingsNetworkBalanceCell"

    private let iconView = UIImageView()
    private let nameLabel = UILabel()
    private let amountLabel = UILabel()
    private let fiatLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.setStyle(.headlineSecondary)

        amountLabel.translatesAutoresizingMaskIntoConstraints = false
        amountLabel.setStyle(.headline)
        amountLabel.textAlignment = .right

        fiatLabel.translatesAutoresizingMaskIntoConstraints = false
        fiatLabel.setStyle(.footnoteSecondary)
        fiatLabel.textAlignment = .right

        let rightStack = UIStackView(arrangedSubviews: [amountLabel, fiatLabel])
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        rightStack.axis = .vertical
        rightStack.alignment = .trailing
        rightStack.spacing = 2

        let leftStack = UIStackView(arrangedSubviews: [iconView, nameLabel])
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        leftStack.axis = .horizontal
        leftStack.alignment = .center
        leftStack.spacing = 12

        let root = UIStackView(arrangedSubviews: [leftStack, UIView(), rightStack])
        root.translatesAutoresizingMaskIntoConstraints = false
        root.axis = .horizontal
        root.alignment = .center

        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),

            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
    }

    func configure(row: NetworkTokenBalanceRow) {
        nameLabel.text = row.networkName
        amountLabel.text = row.tokenAmountText
        fiatLabel.text = row.fiatText

        if let image = UIImage(named: "ico-chain-\(row.chainId)") {
            iconView.image = image
        } else {
            iconView.image = nil
        }
    }
}


