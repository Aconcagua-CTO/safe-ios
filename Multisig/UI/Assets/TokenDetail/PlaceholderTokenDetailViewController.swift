import UIKit

final class PlaceholderTokenDetailViewController: UIViewController {
    private let token: TokenBalance
    private weak var balancesProvider: TokenDetailBalancesProvider?

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let messageLabel = UILabel()
    private let actionContainer = UIView()
    private let singleActionButton = UIButton(type: .system)
    private let leftActionButton = UIButton(type: .system)
    private let rightActionButton = UIButton(type: .system)
    private let dualButtonsStack = UIStackView()

    private var rows: [NetworkTokenBalanceRow] = []
    private var invertirFlowCoordinator: InvertirFromTokenDetailFlowCoordinator?
    private var buyFlowCoordinator: InvestBuyFlowCoordinator?
    private var sellFlowCoordinator: InvestSellFlowCoordinator?
    private let marketPriceService = MarketPriceService()
    private let krakenTickerClient = KrakenTickerClient()
    private var buyPriceTasks: [URLSessionTask] = []

    init(token: TokenBalance, balancesProvider: TokenDetailBalancesProvider?) {
        self.token = token
        self.balancesProvider = balancesProvider
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        buyPriceTasks.forEach { $0.cancel() }
        buyPriceTasks.removeAll()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .backgroundPrimary
        title = token.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        configureTable()
        configureMessageLabel()
        configureActionButtons()
        applyButtonsLayout()
        reloadRows()
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
        tableView.register(SavingsNetworkBalanceCell.self,
                           forCellReuseIdentifier: SavingsNetworkBalanceCell.reuseIdentifier)
        tableView.dataSource = self
        tableView.delegate = self
    }

    private func configureMessageLabel() {
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.setStyle(.body)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.text = "Próximamente mas detalles del activo"
    }

    private func configureActionButtons() {
        actionContainer.translatesAutoresizingMaskIntoConstraints = false

        singleActionButton.translatesAutoresizingMaskIntoConstraints = false
        leftActionButton.translatesAutoresizingMaskIntoConstraints = false
        rightActionButton.translatesAutoresizingMaskIntoConstraints = false
        dualButtonsStack.translatesAutoresizingMaskIntoConstraints = false
        dualButtonsStack.axis = .horizontal
        dualButtonsStack.spacing = 12
        dualButtonsStack.distribution = .fillEqually
        dualButtonsStack.addArrangedSubview(leftActionButton)
        dualButtonsStack.addArrangedSubview(rightActionButton)

        view.addSubview(tableView)
        view.addSubview(messageLabel)
        view.addSubview(actionContainer)
        actionContainer.addSubview(singleActionButton)
        actionContainer.addSubview(dualButtonsStack)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: messageLabel.topAnchor, constant: -12),

            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            messageLabel.bottomAnchor.constraint(equalTo: actionContainer.topAnchor, constant: -16),

            actionContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            actionContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            actionContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            actionContainer.heightAnchor.constraint(equalToConstant: 56),

            singleActionButton.topAnchor.constraint(equalTo: actionContainer.topAnchor),
            singleActionButton.leadingAnchor.constraint(equalTo: actionContainer.leadingAnchor),
            singleActionButton.trailingAnchor.constraint(equalTo: actionContainer.trailingAnchor),
            singleActionButton.bottomAnchor.constraint(equalTo: actionContainer.bottomAnchor),

            dualButtonsStack.topAnchor.constraint(equalTo: actionContainer.topAnchor),
            dualButtonsStack.leadingAnchor.constraint(equalTo: actionContainer.leadingAnchor),
            dualButtonsStack.trailingAnchor.constraint(equalTo: actionContainer.trailingAnchor),
            dualButtonsStack.bottomAnchor.constraint(equalTo: actionContainer.bottomAnchor)
        ])
    }

    private func applyButtonsLayout() {
        singleActionButton.removeTarget(nil, action: nil, for: .allEvents)
        leftActionButton.removeTarget(nil, action: nil, for: .allEvents)
        rightActionButton.removeTarget(nil, action: nil, for: .allEvents)

        let sectionId = TokenCategory.sectionId(for: token.category)
        switch sectionId {
        case TokenCategory.sectionUSD:
            singleActionButton.setText(NSLocalizedString("ui_invertir_progress_title", comment: "Invertir button title"), .filled)
            singleActionButton.addTarget(self, action: #selector(didTapInvertir), for: .touchUpInside)
            singleActionButton.isHidden = false
            dualButtonsStack.isHidden = true
        case TokenCategory.sectionMoneyMarket:
            leftActionButton.setText(NSLocalizedString("ui_invertir_progress_title", comment: "Invertir button title"), .filled)
            leftActionButton.addTarget(self, action: #selector(didTapInvertir), for: .touchUpInside)
            rightActionButton.setText(NSLocalizedString("ui_balance_withdraw_action", comment: "Withdraw action"), .filled)
            rightActionButton.addTarget(self, action: #selector(didTapRetirar), for: .touchUpInside)
            singleActionButton.isHidden = true
            dualButtonsStack.isHidden = false
        default:
            leftActionButton.setText(NSLocalizedString("ui_invertir_buy_action", comment: "Invertir buy action"), .filled)
            leftActionButton.addTarget(self, action: #selector(didTapComprar), for: .touchUpInside)
            rightActionButton.setText(NSLocalizedString("ui_vender_sell_action", comment: "Vender sell action"), .filled)
            rightActionButton.addTarget(self, action: #selector(didTapVender), for: .touchUpInside)
            singleActionButton.isHidden = true
            dualButtonsStack.isHidden = false
        }
    }

    private func reloadRows() {
        rows = balancesProvider?.savingsBreakdownRows(for: token) ?? []
        tableView.reloadData()
    }

    @objc private func didTapInvertir() {
        guard let nav = navigationController else { return }
        let cached = LatestBalancesCache.shared.retrieve(chainId: nil) ?? []
        let availableUsdBalanceFiat = computeAvailableUsdBalanceFiat()
#if DEBUG
        LogService.shared.debug(
            "[Invertir][TokenDetail] start symbol=\(token.symbol) section=\(TokenCategory.sectionId(for: token.category)) " +
            "availableUsd=\(availableUsdBalanceFiat)"
        )
#endif
        if !cached.isEmpty && availableUsdBalanceFiat <= 0 {
            showNoUsdTokensAlert()
            return
        }
        let flow = InvertirFromTokenDetailFlowCoordinator(navigationController: nav,
                                                          token: token,
                                                          availableUsdBalanceFiat: availableUsdBalanceFiat)
        flow.onFinish = { [weak self] in
            self?.invertirFlowCoordinator = nil
        }
        invertirFlowCoordinator = flow
        flow.start()
    }

    private func showNoUsdTokensAlert() {
        let noUsdVC = InvestNoUsdTokensViewController()
        noUsdVC.onDismiss = { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
        navigationController?.pushViewController(noUsdVC, animated: true)
    }

    @objc private func didTapRetirar() {
        let transferAmountVC = TransferAmountViewController()
        transferAmountVC.tokenBalance = token
        let ribbon = RibbonViewController(rootViewController: transferAmountVC)
        navigationController?.pushViewController(ribbon, animated: true)
    }

    @objc private func didTapComprar() {
        if InvestBuyFlowCoordinator.shouldShowNoUsdScreen {
            showNoUsdTokensAlert()
            return
        }
        resolveBuyUnitPrice { [weak self] unitPrice in
            guard let self else { return }
            let flow = InvestBuyFlowCoordinator(presenter: self)
            flow.onDismiss = { [weak self] in
                self?.buyFlowCoordinator = nil
            }
            self.buyFlowCoordinator = flow
            self.buyFlowCoordinator?.startWithToken(self.token, unitPriceFiatPerToken: unitPrice)
        }
    }

    @objc private func didTapVender() {
        let flow = InvestSellFlowCoordinator(presenter: self)
        flow.onDismiss = { [weak self] in
            self?.sellFlowCoordinator = nil
        }
        sellFlowCoordinator = flow
        sellFlowCoordinator?.startWithToken(token)
    }

    private func resolveBuyUnitPrice(completion: @escaping (Double?) -> Void) {
        buyPriceTasks.forEach { $0.cancel() }
        buyPriceTasks.removeAll()

        // Fast path from already-enriched token.
        if token.fiatConversion > 0 {
            completion(token.fiatConversion)
            return
        }
        let source = (token.priceSource ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sourceParam = (token.priceSourceParam ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if source == "fixed", let fixed = Double(sourceParam), fixed > 0 {
            completion(fixed)
            return
        }

        // Kraken quote fallback for assets priced with a direct Kraken pair.
        if source == "kraken", !sourceParam.isEmpty {
            let task = krakenTickerClient.fetchLastPrices(pairs: [sourceParam]) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let snapshot):
                        completion(snapshot.pricesByPair[sourceParam])
                    case .failure:
                        completion(nil)
                    }
                }
            }
            if let task { buyPriceTasks.append(task) }
            return
        }

        // Markets-price fallback by symbol/address (same source used by Invertir markets).
        let safe = try? Safe.getSelected()
        let chainId = (safe?.chain?.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chainId.isEmpty else {
            completion(nil)
            return
        }
        let network = safe?.chain?.shortName
        let entries = TokenWhitelist.markets(chainId: chainId, network: network)
        let symbolUpper = tokenDisplaySymbol.uppercased()
        let tokenAddressLower = token.address.lowercased()

        let candidates = entries.filter { entry in
            let entryWrap = (entry.wrapLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let entrySymbol = (entry.tokenSymbol ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let entryDisplay = (entryWrap.isEmpty ? entrySymbol : entryWrap).uppercased()
            guard entryDisplay == symbolUpper else { return false }
            return true
        }
        guard !candidates.isEmpty else {
            completion(nil)
            return
        }

        let tasks = marketPriceService.fetchPrices(entries: candidates) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let snapshot):
                    let pricesByLower = Dictionary(uniqueKeysWithValues: snapshot.pricesByAddress.map { ($0.key.lowercased(), $0.value) })
                    if let direct = pricesByLower[tokenAddressLower], direct > 0 {
                        completion(direct)
                        return
                    }
                    for entry in candidates {
                        let addr = (entry.networkAddress ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        if let v = pricesByLower[addr], v > 0 {
                            completion(v)
                            return
                        }
                    }
                    completion(nil)
                case .failure:
                    completion(nil)
                }
                self.buyPriceTasks.removeAll()
            }
        }
        buyPriceTasks.append(contentsOf: tasks)
    }

    private var tokenDisplaySymbol: String {
        let wrap = (token.wrapLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (wrap.isEmpty ? token.symbol : wrap).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func computeAvailableUsdBalanceFiat() -> Double {
        guard let latest = LatestBalancesCache.shared.retrieve(chainId: nil), !latest.isEmpty else {
            return 0
        }

        let usdItems = latest.filter { TokenCategory.sectionId(for: $0.category) == TokenCategory.sectionUSD }
        let total = usdItems.reduce(0.0) { partial, item in
            partial + max(0, item.fiatValue)
        }

#if DEBUG
        let debugItems = usdItems.map { item in
            let display = ((item.wrapLabel ?? "").isEmpty ? item.symbol : (item.wrapLabel ?? item.symbol))
            return "\(display):\(item.fiatValue)"
        }.joined(separator: ", ")
        LogService.shared.debug("[Invertir][TokenDetail] usdFundingBalances=[\(debugItems)] total=\(total)")
#endif

        return total
    }
}

extension PlaceholderTokenDetailViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = rows[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: SavingsNetworkBalanceCell.reuseIdentifier,
                                                 for: indexPath) as! SavingsNetworkBalanceCell
        cell.configure(row: row)
        return cell
    }
}


