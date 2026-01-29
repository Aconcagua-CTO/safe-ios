//
//  InvertirViewController.swift
//  Multisig
//
//  Created by Assistant on 12/18/25.
//

import UIKit
import Ethereum
import SwiftCryptoTokenFormatter

/// Container for the Invertir tab. Mirrors AssetsViewController but uses the invertir balances list.
class InvertirViewController: AssetsViewController {
    private var investBuyFlow: InvestBuyFlowCoordinator?
    private var investSellFlow: InvestSellFlowCoordinator?

    init() {
        // Use the LoadableViewController nib so outlets (tableView, etc.) are loaded.
        let invertirBalances = InvertirBalancesViewController(
            namedClass: LoadableViewController.self
        )
        super.init(balancesViewController: invertirBalances, nibName: "InvertirAssetsViewController")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        LogService.shared.debug("[InvertirTab] viewDidLoad vc=\(String(describing: type(of: self)))")

        // Invertir: "+ Comprar" should start the Invest buy flow (not the receive/address modal).
        totalBalanceView.onReceivedClicked = { [weak self] in
            self?.launchBuyFlow()
        }

        // Invertir: "- Vender" should start the Invest sell flow.
        totalBalanceView.onSendClicked = { [weak self] in
            self?.launchSellFlow()
        }

    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Invertir lists "markets" (no balances), so reuse the exact total computed by Assets tab.
        // This avoids extra network calls + avoids showing 0.00 when prices are missing.
        updateHeaderFromAssetsCacheIfAvailable()
    }

    private func launchBuyFlow() {
        let flow = InvestBuyFlowCoordinator(presenter: self)
        flow.onDismiss = { [weak self] in
            self?.investBuyFlow = nil
        }
        investBuyFlow = flow
        investBuyFlow?.start()
    }

    private func launchSellFlow() {
        let flow = InvestSellFlowCoordinator(presenter: self)
        flow.onDismiss = { [weak self] in
            self?.investSellFlow = nil
        }
        investSellFlow = flow
        investSellFlow?.start()
    }

    private var invertirBalancesViewController: InvertirBalancesViewController? {
        if let current = selectedViewController as? InvertirBalancesViewController {
            return current
        }
        return viewControllers.first { $0 is InvertirBalancesViewController } as? InvertirBalancesViewController
    }

    // MARK: - Header balance (same as Assets tab)

    private func updateHeaderFromAssetsCacheIfAvailable() {
        guard let safe = try? Safe.getSelected() else { return }
        let chainId = safe.chain?.id
        if let cachedTotal = LatestBalancesCache.shared.retrieveTotalFiat(chainId: chainId) {
            totalBalanceView.amount = cachedTotal
            totalBalanceView.loading = false
        }

        // Keep Vender enabled/disabled consistent with Assets (non-zero owned balances).
        let cachedBalances = LatestBalancesCache.shared.retrieve(chainId: chainId) ?? []
        if !cachedBalances.isEmpty {
            totalBalanceView.sendEnabled = cachedBalances.contains(where: { $0.balanceValue.value > 0 })
        }
    }
}

// MARK: - InvestSelectTokenViewController (Buy token picker)

final class InvestSelectTokenViewController: UIViewController {
    struct BalanceCategorySection {
        let id: String
        let title: String
        let items: [TokenBalance]
    }

    var onTokenSelected: ((TokenBalance, Double?) -> Void)?
    var onLoadedBalances: (([TokenBalance]) -> Void)?

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchController = UISearchController(searchResultsController: nil)
    
    private var currentTask: URLSessionTask?
    private var sections: [BalanceCategorySection] = []
    private var isWhitelistSyncInProgress = false
    /// Prevent an infinite loop when backend returns an empty whitelist (`[]`).
    private var didReceiveEmptyWhitelistFromBackend = false

    private var searchTerm: String = ""
    private var allMarketItems: [TokenBalance] = []
    private var tokenChangePct24h: [String: Double] = [:] // token address -> 24h % change
    private var tokenPrices: [String: Double] = [:] // token address -> unit price (USD)
    private var marketPriceTasks: [URLSessionTask] = []
    private let marketPriceService = MarketPriceService()

    private var clientGatewayService: BalancesAPI {
        guard let chain = try? Safe.getSelected()?.chain else {
            return App.shared.clientGatewayService
        }
        return chain.gatewayService()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .backgroundPrimary

        navigationItem.title = NSLocalizedString("ui_invertir_select_asset_title", comment: "Invertir select asset title")
        ViewControllerFactory.addCloseButton(self)

        configureTable()
        configureSearch()

        loadBalances()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Avoid leaking a running request if the modal is dismissed.
        currentTask?.cancel()
        marketPriceTasks.forEach { $0.cancel() }
        marketPriceTasks = []
    }

    private func configureTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .backgroundPrimary
        tableView.separatorColor = .separator
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 76
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }

        // Use the Invertir-specific cell layout, but keep the same reuse identifier expected by the nib.
        tableView.register(
            UINib(nibName: "InvertirBalanceTableViewCell", bundle: nil),
            forCellReuseIdentifier: "BalanceTableViewCell"
        )
        tableView.registerHeaderFooterView(BasicHeaderView.self)

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

    // MARK: - Search

    private func configureSearch() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = NSLocalizedString("ui_assets_search_tokens_placeholder", comment: "Search tokens placeholder")
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.searchBar.autocapitalizationType = .none
        
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    private func filteredItems(from items: [TokenBalance], term: String) -> [TokenBalance] {
        let t = term.lowercased()
        guard !t.isEmpty else { return items }
        return items.filter { item in
            item.symbol.lowercased().contains(t)
            || item.name.lowercased().contains(t)
            || item.category.lowercased().contains(t)
        }
    }

    private func loadBalances() {
        // Markets: list is derived from whitelist (not user balances).
        guard let safe = try? Safe.getSelected(), let chain = safe.chain else {
            sections = []
            tableView.reloadData()
            return
        }

        let chainId = chain.id ?? ""
        let totalWhitelist = TokenWhitelist.all.count

        if totalWhitelist == 0, !isWhitelistSyncInProgress {
            if didReceiveEmptyWhitelistFromBackend {
                sections = []
                tableView.reloadData()
                return
            }
            isWhitelistSyncInProgress = true
            App.shared.tokenWhitelistRepository.syncWhitelist(force: false, network: nil) { [weak self] result in
                guard let self else { return }
                self.isWhitelistSyncInProgress = false
                switch result {
                case .success:
                    if TokenWhitelist.all.count == 0 {
                        self.didReceiveEmptyWhitelistFromBackend = true
                    } else {
                        self.didReceiveEmptyWhitelistFromBackend = false
                    }
                    self.loadBalances()
                case .failure(let error):
                    self.didReceiveEmptyWhitelistFromBackend = false
                    LogService.shared.error("[InvestMarkets] Whitelist sync failed: \(error.localizedDescription)")
                    self.sections = []
                    self.tableView.reloadData()
                }
            }
            return
        }

        let entries = TokenWhitelist.markets(chainId: chainId, network: chain.shortName)

        // Keep ALL markets (including stablecoins/savings) in memory so Screen 2 can show
        // available "pay with" assets. Screen 1 selection still excludes savings via `makeSections`.
        let balances: [TokenBalance] = entries.compactMap { entry in
            TokenBalance(whitelist: entry)
        }

        self.onLoadedBalances?(balances)
        self.allMarketItems = balances
        self.sections = self.makeSections(items: filteredItems(from: balances, term: searchTerm))
        self.tableView.reloadData()

        let shownEntries = entries.filter { entry in
            !TokenCategory.isSavings(entry.tokenCategory)
                && TokenCategory.isAllowedInvestTarget(entry.tokenCategory)
        }
        fetchPricesForMarketTokens(entries: shownEntries)
    }
}

extension InvestSelectTokenViewController {
    private var sectionOrder: [(id: String, title: String)] {
        [
            // Match the main Invertir screen ordering (`InvertirBalancesViewController.balanceSectionOrder`)
            (id: TokenCategory.sectionMoneyMarket, title: "Money market"),
            (id: TokenCategory.sectionAcciones, title: "Acciones"),
            (id: TokenCategory.sectionEtfIndices, title: "ETF de indices"),
            (id: TokenCategory.sectionEtfOtros, title: "ETF otros"),
            (id: TokenCategory.sectionCripto, title: "Cripto"),
            (id: TokenCategory.sectionOro, title: "Oro"),
            (id: TokenCategory.sectionOtros, title: "Otros"),
            (id: TokenCategory.sectionBlackToken, title: "blackToken")
        ]
    }

    private func isSavings(_ item: TokenBalance) -> Bool {
        TokenCategory.isSavings(item.category)
    }

    /// Allowed categories for the *target* (what the user buys) in v1.
    private func isAllowedTarget(_ item: TokenBalance) -> Bool {
        TokenCategory.isAllowedInvestTarget(item.category)
    }

    private func mapCategoryToSectionId(_ item: TokenBalance) -> String {
        TokenCategory.sectionId(for: item.category)
    }

    private func makeSections(items: [TokenBalance]) -> [BalanceCategorySection] {
        let filtered = items.filter { item in
            !isSavings(item) && isAllowedTarget(item)
        }

        var grouped: [String: [TokenBalance]] = [:]
        for item in filtered {
            grouped[mapCategoryToSectionId(item), default: []].append(item)
        }

        return sectionOrder.compactMap { entry in
            guard let balances = grouped[entry.id], !balances.isEmpty else { return nil }
            let sorted = balances.sorted { lhs, rhs in
                if lhs.fiatValue == rhs.fiatValue {
                    return lhs.symbol.localizedCaseInsensitiveCompare(rhs.symbol) == .orderedAscending
                }
                return lhs.fiatValue > rhs.fiatValue
            }
            return BalanceCategorySection(id: entry.id, title: entry.title, items: sorted)
        }
    }

    private func configureBadge(for cell: BalanceTableViewCell, item: TokenBalance, section: BalanceCategorySection) {
        // Keep the exact same badge logic as `InvertirBalancesViewController`.
        if section.id == TokenCategory.sectionUSD {
            cell.setBadge(text: "3.75%")
        } else if section.id == TokenCategory.sectionMoneyMarket || TokenCategory.isMoneyMarket(item.category) {
            cell.setBadge(text: "3.75%", backgroundColor: .success)
        } else if [
            TokenCategory.sectionCripto,
            TokenCategory.sectionAcciones,
            TokenCategory.sectionEtfIndices,
            TokenCategory.sectionEtfOtros,
            TokenCategory.sectionOro
        ].contains(section.id) {
            if let change = tokenChangePct24h[item.address], change.isFinite {
                let isAscending = change >= 0
                let triangle = isAscending ? "▲" : "▼"
                let color: UIColor = isAscending ? .success : .error
                let text = formatChangePct(change)
                cell.setBadge(text: text,
                              backgroundColor: .clear,
                              textColor: color,
                              prefix: triangle,
                              prefixColor: color)
            } else {
                cell.setBadge(text: nil)
            }
        } else {
            cell.setBadge(text: nil)
        }
    }

    private func fetchPricesForMarketTokens(entries: [TokenWhitelist]) {
        marketPriceTasks.forEach { $0.cancel() }
        marketPriceTasks = []

        marketPriceTasks = marketPriceService.fetchPrices(entries: entries) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let snapshot):
                    self.tokenChangePct24h = snapshot.changePct24hByAddress
                    self.tokenPrices = snapshot.pricesByAddress
                    self.tableView.reloadData()
                case .failure:
                    break
                }
            }
        }
    }

    private func formatChangePct(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "-"
        let absValue = abs(value)
        let formatted = String(format: "%.2f", absValue)
        return "\(sign)\(formatted)%"
    }
}

extension InvestSelectTokenViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = sections[indexPath.section]
        let item = section.items[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "BalanceTableViewCell", for: indexPath) as! BalanceTableViewCell

        cell.setMainText(item.symbol)
        // Invertir hides fiat + amount in the list.
        cell.setDetailText("")
        cell.setSubDetailText("")
        configureBadge(for: cell, item: item, section: section)

        if let image = item.image {
            cell.setImage(image)
        } else {
            cell.setImage(with: item.imageURL, placeholder: UIImage(named: "ico-token-placeholder")!)
        }

        cell.selectionStyle = .default
        return cell
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection sectionIndex: Int) -> UIView? {
        let section = sections[sectionIndex]
        let view = tableView.dequeueHeaderFooterView(BasicHeaderView.self)
        view.setName(section.title)
        return view
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection sectionIndex: Int) -> CGFloat {
        BasicHeaderView.headerHeight
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let section = sections[indexPath.section]
        let item = section.items[indexPath.row]
        let unitPrice = tokenPrices[item.address]
        onTokenSelected?(item, unitPrice)
    }
}

extension InvestSelectTokenViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let raw = searchController.searchBar.text ?? ""
        searchTerm = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        
        sections = makeSections(items: filteredItems(from: allMarketItems, term: searchTerm))
        tableView.reloadData()
    }
}

// MARK: - Sell token picker

final class InvestSellSourceSelectViewController: UIViewController {
    struct BalanceCategorySection {
        let id: String
        let title: String
        let items: [TokenBalance]
    }

    var onTokenSelected: ((TokenBalance) -> Void)?

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchController = UISearchController(searchResultsController: nil)
    
    private var currentTask: URLSessionTask?
    private var sections: [BalanceCategorySection] = []

    private var searchTerm: String = ""
    private var allBalances: [TokenBalance] = []

    private var clientGatewayService: BalancesAPI {
        guard let chain = try? Safe.getSelected()?.chain else {
            return App.shared.clientGatewayService
        }
        return chain.gatewayService()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .backgroundPrimary

        navigationItem.title = NSLocalizedString("ui_invertir_sell_select_source_title", comment: "Invertir sell select source title")
        ViewControllerFactory.addCloseButton(self)

        configureTable()
        configureSearch()

        loadBalances()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Avoid leaking a running request if the modal is dismissed.
        currentTask?.cancel()
    }

    private func configureTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .backgroundPrimary
        tableView.separatorColor = .separator
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 76
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }

        tableView.register(
            UINib(nibName: "InvertirBalanceTableViewCell", bundle: nil),
            forCellReuseIdentifier: "BalanceTableViewCell"
        )
        tableView.registerHeaderFooterView(BasicHeaderView.self)

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

    private func configureSearch() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = NSLocalizedString("ui_assets_search_tokens_placeholder", comment: "Search tokens placeholder")
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.searchBar.autocapitalizationType = .none
        
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    private func filteredItems(from items: [TokenBalance], term: String) -> [TokenBalance] {
        let t = term.lowercased()
        guard !t.isEmpty else { return items }
        return items.filter { item in
            item.symbol.lowercased().contains(t)
            || item.name.lowercased().contains(t)
            || item.category.lowercased().contains(t)
        }
    }

    private func loadBalances() {
        guard let safe = try? Safe.getSelected(), let chain = safe.chain else {
            sections = []
            tableView.reloadData()
            return
        }

        let chainId = chain.id ?? ""

        // Sell: show all balances with non-zero holdings and that are allowed for selling.
        let cachedBalances = LatestBalancesCache.shared.retrieve(chainId: chainId) ?? []
        let available = cachedBalances.filter { item in
            item.balanceValue.value > 0 && TokenCategory.isAllowedInvestSource(item.category)
        }

        self.allBalances = available
        self.sections = makeSections(items: filteredItems(from: available, term: searchTerm))
        self.tableView.reloadData()
    }
}

extension InvestSellSourceSelectViewController {
    private var sectionOrder: [(id: String, title: String)] {
        [
            (id: TokenCategory.sectionUSD, title: ""),
            (id: TokenCategory.sectionMoneyMarket, title: "Money market"),
            (id: TokenCategory.sectionAcciones, title: "Acciones"),
            (id: TokenCategory.sectionEtfIndices, title: "ETF de indices"),
            (id: TokenCategory.sectionEtfOtros, title: "ETF otros"),
            (id: TokenCategory.sectionCripto, title: "Cripto"),
            (id: TokenCategory.sectionOro, title: "Oro"),
            (id: TokenCategory.sectionOtros, title: "Otros"),
            (id: TokenCategory.sectionBlackToken, title: "blackToken")
        ]
    }

    private func mapCategoryToSectionId(_ item: TokenBalance) -> String {
        TokenCategory.sectionId(for: item.category)
    }

    private func makeSections(items: [TokenBalance]) -> [BalanceCategorySection] {
        var grouped: [String: [TokenBalance]] = [:]
        for item in items {
            grouped[mapCategoryToSectionId(item), default: []].append(item)
        }

        return sectionOrder.compactMap { entry in
            guard let balances = grouped[entry.id], !balances.isEmpty else { return nil }
            let sorted = balances.sorted { lhs, rhs in
                if lhs.fiatValue == rhs.fiatValue {
                    return lhs.symbol.localizedCaseInsensitiveCompare(rhs.symbol) == .orderedAscending
                }
                return lhs.fiatValue > rhs.fiatValue
            }
            return BalanceCategorySection(id: entry.id, title: entry.title, items: sorted)
        }
    }

    private func configureBadge(for cell: BalanceTableViewCell, item: TokenBalance, section: BalanceCategorySection) {
        if section.id == TokenCategory.sectionUSD {
            cell.setBadge(text: "3.75%")
        } else if section.id == TokenCategory.sectionMoneyMarket || TokenCategory.isMoneyMarket(item.category) {
            cell.setBadge(text: "3.75%", backgroundColor: .success)
        } else {
            cell.setBadge(text: nil)
        }
    }
}

extension InvestSellSourceSelectViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = sections[indexPath.section]
        let item = section.items[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "BalanceTableViewCell", for: indexPath) as! BalanceTableViewCell

        cell.setMainText(item.symbol)
        // Show balance in detail and fiat in sub-detail
        cell.setDetailText(item.balance)
        cell.setSubDetailText(item.fiatBalance)
        configureBadge(for: cell, item: item, section: section)

        if let image = item.image {
            cell.setImage(image)
        } else {
            cell.setImage(with: item.imageURL, placeholder: UIImage(named: "ico-token-placeholder")!)
        }

        cell.selectionStyle = .default
        return cell
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection sectionIndex: Int) -> UIView? {
        let section = sections[sectionIndex]
        if section.title.isEmpty { return nil }
        let view = tableView.dequeueHeaderFooterView(BasicHeaderView.self)
        view.setName(section.title)
        return view
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection sectionIndex: Int) -> CGFloat {
        let section = sections[sectionIndex]
        if section.title.isEmpty { return 0 }
        return BasicHeaderView.headerHeight
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let section = sections[indexPath.section]
        let item = section.items[indexPath.row]
        onTokenSelected?(item)
    }
}

extension InvestSellSourceSelectViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let raw = searchController.searchBar.text ?? ""
        searchTerm = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        
        sections = makeSections(items: filteredItems(from: allBalances, term: searchTerm))
        tableView.reloadData()
    }
}

// MARK: - Shared balances cache

final class LatestBalancesCache {
    static let shared = LatestBalancesCache()
    private init() {}

    private let queue = DispatchQueue(label: "io.gnosis.multisig.latestbalancescache")
    private var balancesByChainId: [String: [TokenBalance]] = [:]
    private var totalFiatByChainId: [String: String] = [:]
    private let defaultKey = "default"

    func update(balances: [TokenBalance], allowAllZero: Bool = false, chainId: String? = nil) {
        if !allowAllZero {
            guard balances.contains(where: { $0.balanceValue.value > 0 }) else { return }
        }
        let key = (chainId ?? defaultKey).trimmingCharacters(in: .whitespacesAndNewlines)
        queue.sync {
            balancesByChainId[key.isEmpty ? defaultKey : key] = balances
        }
    }

    func updateTotalFiat(totalFiat: String?, chainId: String? = nil) {
        let trimmed = (totalFiat ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let key = (chainId ?? defaultKey).trimmingCharacters(in: .whitespacesAndNewlines)
        queue.sync {
            // Always store a "global" last total so other tabs can reuse it even when their chain differs.
            totalFiatByChainId[defaultKey] = trimmed
            totalFiatByChainId[key.isEmpty ? defaultKey : key] = trimmed
        }
    }

    func retrieve(chainId: String?) -> [TokenBalance]? {
        let key = (chainId ?? defaultKey).trimmingCharacters(in: .whitespacesAndNewlines)
        return queue.sync {
            if let stored = balancesByChainId[key], !stored.isEmpty {
                return stored
            }
            return balancesByChainId[defaultKey]
        }
    }

    func retrieveTotalFiat(chainId: String?) -> String? {
        let key = (chainId ?? defaultKey).trimmingCharacters(in: .whitespacesAndNewlines)
        return queue.sync {
            if let value = totalFiatByChainId[key], !value.isEmpty {
                return value
            }
            return totalFiatByChainId[defaultKey]
        }
    }
}

// MARK: - Invest (Comprar) Flow - Model

struct InvestBuyDraft {
    let selectedToken: TokenBalance
    let savingsTotalFiat: Double
    let investAmountFiat: Double
    let unitPriceFiatPerToken: Double
    let buyQuantity: Double
    let remainingSavingsFiat: Double
    let fiatCode: String
}

// MARK: - Invest (Comprar) Flow - Screen 2

/// Screen 2: user enters how much they want to invest (in fiat).
final class InvestEnterAmountViewController: UIViewController, UITextFieldDelegate {
    var onContinue: ((InvestBuyDraft) -> Void)?

    private let selectedToken: TokenBalance
    private let fiatCode: String
    private var paymentBalances: [TokenBalance]
    private var selectedPaymentToken: TokenBalance?
    private var unitPriceFiatPerToken: Double?

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stack = UIStackView()

    private let paymentAssetsTableView = UITableView(frame: .zero, style: .plain)
    private var paymentAssetsTableHeightConstraint: NSLayoutConstraint?

    private let amountTitleLabel = UILabel()
    private let amountField = UITextField()
    private let amountErrorLabel = UILabel()

    private let assetTitleLabel = UILabel()
    private let assetRow = UIView()
    private let assetSymbolLabel = UILabel()
    private let assetPriceLabel = UILabel()

    private let quantityTitleLabel = UILabel()
    private let quantityValueLabel = UILabel()

    private let continueButton = UIButton(type: .system)

    private var keyboardBehavior: KeyboardAvoidingBehavior!
    private var keyboardToolbar: UIToolbar!

    private var debounceTimer: Timer?
    private let debounceDuration: TimeInterval = 0.15

    init(selectedToken: TokenBalance,
         paymentTotalFiat _: Double,
         fiatCode: String,
         paymentBalances: [TokenBalance],
         unitPriceFiatPerToken: Double?) {
        self.selectedToken = selectedToken
        self.fiatCode = fiatCode
        self.paymentBalances = paymentBalances
        self.selectedPaymentToken = paymentBalances.first
        self.unitPriceFiatPerToken = unitPriceFiatPerToken
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .backgroundPrimary

        title = NSLocalizedString("ui_invertir_payment_method_title", comment: "Invertir payment method title")

        configureLayout()
        configureKeyboardBehavior()
        configureInitialValues()
        recompute()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        keyboardBehavior.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        keyboardBehavior.stop()
        TooltipSource.hideAll()
    }

    func updatePaymentBalances(_ balances: [TokenBalance], totalFiat _: Double) {
        paymentBalances = balances
        if let current = selectedPaymentToken,
           let match = balances.first(where: { $0.address == current.address }) {
            selectedPaymentToken = match
        } else {
            selectedPaymentToken = balances.first
        }

        let height = CGFloat(paymentBalances.count) * paymentAssetsTableView.rowHeight
        paymentAssetsTableHeightConstraint?.constant = max(0, height)
        paymentAssetsTableView.reloadData()
        applySelectedPaymentSelection(animated: false)
        recompute()
    }

    private func configureLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        scrollView.keyboardDismissMode = .interactive

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 12
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24)
        ])

        configurePaymentAssetsTable()

        amountTitleLabel.setStyle(.caption1Medium)
        amountTitleLabel.textColor = .labelSecondary
        amountTitleLabel.text = "Monto a invertir"

        amountField.translatesAutoresizingMaskIntoConstraints = false
        amountField.setStyle(.headline)
        amountField.textColor = .labelPrimary
        amountField.backgroundColor = .backgroundSecondary
        amountField.layer.cornerRadius = 10
        amountField.layer.masksToBounds = true
        amountField.keyboardType = .decimalPad
        amountField.placeholder = "0"
        amountField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        amountField.leftViewMode = .always
        amountField.delegate = self
        amountField.addTarget(self, action: #selector(amountDidChange), for: .editingChanged)
        NSLayoutConstraint.activate([
            amountField.heightAnchor.constraint(equalToConstant: 56)
        ])

        amountErrorLabel.setStyle(.caption1)
        amountErrorLabel.textColor = .error
        amountErrorLabel.numberOfLines = 0
        amountErrorLabel.isHidden = true

        assetTitleLabel.setStyle(.caption1Medium)
        assetTitleLabel.textColor = .labelSecondary
        assetTitleLabel.text = "Activo seleccionado"

        assetRow.translatesAutoresizingMaskIntoConstraints = false
        assetRow.backgroundColor = .backgroundSecondary
        assetRow.layer.cornerRadius = 10
        assetRow.layer.masksToBounds = true

        assetSymbolLabel.translatesAutoresizingMaskIntoConstraints = false
        assetSymbolLabel.setStyle(.headline)
        assetSymbolLabel.textColor = .labelPrimary

        assetPriceLabel.translatesAutoresizingMaskIntoConstraints = false
        assetPriceLabel.setStyle(.headlineSecondary)
        assetPriceLabel.textColor = .labelSecondary
        assetPriceLabel.textAlignment = .right

        assetRow.addSubview(assetSymbolLabel)
        assetRow.addSubview(assetPriceLabel)
        NSLayoutConstraint.activate([
            assetRow.heightAnchor.constraint(equalToConstant: 56),

            assetSymbolLabel.leadingAnchor.constraint(equalTo: assetRow.leadingAnchor, constant: 12),
            assetSymbolLabel.centerYAnchor.constraint(equalTo: assetRow.centerYAnchor),

            assetPriceLabel.trailingAnchor.constraint(equalTo: assetRow.trailingAnchor, constant: -12),
            assetPriceLabel.centerYAnchor.constraint(equalTo: assetRow.centerYAnchor),
            assetPriceLabel.leadingAnchor.constraint(greaterThanOrEqualTo: assetSymbolLabel.trailingAnchor, constant: 12)
        ])

        quantityTitleLabel.setStyle(.caption1Medium)
        quantityTitleLabel.textColor = .labelSecondary
        quantityTitleLabel.text = NSLocalizedString("ui_invertir_quantity_title", comment: "Invertir quantity title")

        quantityValueLabel.setStyle(.title3)
        quantityValueLabel.textColor = .labelPrimary

        continueButton.setText(NSLocalizedString("button_continue", comment: "Continue button title"), .filled)
        continueButton.isEnabled = false
        continueButton.addTarget(self, action: #selector(didTapContinue), for: .touchUpInside)
        NSLayoutConstraint.activate([
            continueButton.heightAnchor.constraint(equalToConstant: 48)
        ])

        stack.addArrangedSubview(paymentAssetsTableView)
        stack.addArrangedSubview(spacer(12))

        stack.addArrangedSubview(amountTitleLabel)
        stack.addArrangedSubview(amountField)
        stack.addArrangedSubview(amountErrorLabel)

        stack.addArrangedSubview(spacer(8))

        stack.addArrangedSubview(assetTitleLabel)
        stack.addArrangedSubview(assetRow)

        stack.addArrangedSubview(spacer(8))

        stack.addArrangedSubview(quantityTitleLabel)
        stack.addArrangedSubview(quantityValueLabel)

        stack.addArrangedSubview(spacer(20))
        stack.addArrangedSubview(continueButton)
    }

    private func configureKeyboardBehavior() {
        keyboardBehavior = KeyboardAvoidingBehavior(scrollView: scrollView)

        keyboardToolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 100, height: 60))
        let done = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(didTapKeyboardDone))
        keyboardToolbar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            done
        ]
        keyboardToolbar.sizeToFit()
        amountField.inputAccessoryView = keyboardToolbar
    }

    private func configurePaymentAssetsTable() {
        paymentAssetsTableView.translatesAutoresizingMaskIntoConstraints = false
        paymentAssetsTableView.backgroundColor = .backgroundPrimary
        paymentAssetsTableView.separatorColor = .separator
        paymentAssetsTableView.rowHeight = 64
        paymentAssetsTableView.estimatedRowHeight = 64
        paymentAssetsTableView.isScrollEnabled = false
        paymentAssetsTableView.allowsSelection = true
        paymentAssetsTableView.tableFooterView = UIView()
        paymentAssetsTableView.register(SelectAssetRowCell.self, forCellReuseIdentifier: SelectAssetRowCell.reuseID)
        paymentAssetsTableView.dataSource = self
        paymentAssetsTableView.delegate = self

        let height = CGFloat(paymentBalances.count) * paymentAssetsTableView.rowHeight
        paymentAssetsTableHeightConstraint = paymentAssetsTableView.heightAnchor.constraint(equalToConstant: max(0, height))
        paymentAssetsTableHeightConstraint?.isActive = true
    }

    private func configureInitialValues() {
        assetSymbolLabel.text = selectedToken.symbol
        applySelectedPaymentSelection(animated: false)
    }

    private func applySelectedPaymentSelection(animated: Bool) {
        guard let selected = selectedPaymentToken else { return }
        guard let idx = paymentBalances.firstIndex(where: { $0.address == selected.address }) else { return }
        let indexPath = IndexPath(row: idx, section: 0)
        paymentAssetsTableView.selectRow(at: indexPath, animated: animated, scrollPosition: .none)
    }

    private func spacer(_ height: CGFloat) -> UIView {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            v.heightAnchor.constraint(equalToConstant: height)
        ])
        return v
    }

    @objc private func amountDidChange() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceDuration, repeats: false) { [weak self] _ in
            self?.recompute()
        }
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        keyboardBehavior.activeTextField = textField
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        return true
    }

    @objc private func didTapKeyboardDone() {
        keyboardBehavior.hideKeyboard()
    }

    @objc private func didTapContinue() {
        let computed = recompute()
        guard let draft = computed else { return }
        onContinue?(draft)
    }

    @discardableResult
    private func recompute() -> InvestBuyDraft? {
        amountErrorLabel.isHidden = true
        continueButton.isEnabled = false

        guard let unitPrice = deriveUnitPriceFiatPerToken(selectedToken) else {
            assetPriceLabel.text = "Precio: —"
            quantityValueLabel.text = "—"
            return nil
        }

        assetPriceLabel.text = "Precio: \(formatFiat(unitPrice, code: fiatCode))"

        guard let paymentToken = selectedPaymentToken else {
            amountErrorLabel.text = "Seleccioná un token para pagar"
            amountErrorLabel.isHidden = false
            quantityValueLabel.text = "—"
            return nil
        }

        guard let amountFiat = parseUserFiatAmount(amountField.text),
              amountFiat > 0
        else {
            quantityValueLabel.text = "—"
            return nil
        }

        if amountFiat > paymentToken.fiatValue + 0.000_000_1 {
            amountErrorLabel.text = "Saldo insuficiente"
            amountErrorLabel.isHidden = false
            quantityValueLabel.text = "—"
            return nil
        }

        let qty = amountFiat / unitPrice
        quantityValueLabel.text = "\(formatNumber5(qty)) \(selectedToken.symbol)"

        let remaining = max(0, paymentToken.fiatValue - amountFiat)
        let draft = InvestBuyDraft(
            selectedToken: selectedToken,
            savingsTotalFiat: paymentToken.fiatValue,
            investAmountFiat: amountFiat,
            unitPriceFiatPerToken: unitPrice,
            buyQuantity: qty,
            remainingSavingsFiat: remaining,
            fiatCode: fiatCode
        )
        continueButton.isEnabled = true
        return draft
    }
}

extension InvestEnterAmountViewController {
    private func deriveUnitPriceFiatPerToken(_ token: TokenBalance) -> Double? {
        if let override = unitPriceFiatPerToken, override > 0 {
            return override
        }
        if token.fiatConversion > 0 {
            return token.fiatConversion
        }
        let totalTokenAmount = decimalValue(from: token.balanceValue)
        guard totalTokenAmount > 0 else { return nil }
        let unit = token.fiatValue / totalTokenAmount
        return unit.isFinite && unit > 0 ? unit : nil
    }

    private func decimalValue(from amount: BigDecimal) -> Double {
        let decimalString = TokenFormatter().string(from: amount,
                                                    decimalSeparator: ".",
                                                    thousandSeparator: "")
        guard let dec = Decimal(string: decimalString) else { return 0 }
        return (dec as NSDecimalNumber).doubleValue
    }

    private func parseUserFiatAmount(_ text: String?) -> Double? {
        let raw = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.autoupdatingCurrent

        if let number = formatter.number(from: raw) {
            return number.doubleValue
        }
        let normalized = raw.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private func formatFiat(_ value: Double, code: String) -> String {
        let fiatString = String(format: "%.6f", max(0, value))
        return TokenBalance.displayCurrency(from: fiatString, code: code)
    }

    private func formatNumber5(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.autoupdatingCurrent
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 5
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.5f", value)
    }
}

// MARK: - Payment assets table (Savings + Money market)

extension InvestEnterAmountViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        paymentBalances.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = paymentBalances[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: SelectAssetRowCell.reuseID, for: indexPath) as! SelectAssetRowCell
        cell.setSymbol(item.symbol)
        cell.setChain("")
        cell.setFiat(item.fiatBalance)
        cell.setAmount(item.balanceFormatted5)
        cell.accessoryType = (item.address == selectedPaymentToken?.address) ? .checkmark : .none

        let normalized = item.category
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
        if normalized == "moneymarket" || normalized == "savings" {
            cell.setBadge(text: "3.75%", backgroundColor: .success)
        } else if normalized == "stablecoin" || normalized == "stablecoins" {
            cell.setBadge(text: nil)
        } else {
            cell.setBadge(text: nil)
        }

        if let image = item.image {
            cell.setImage(image)
        } else {
            cell.setImage(with: item.imageURL, placeholder: UIImage(named: "ico-token-placeholder")!)
        }
        return cell
    }
}

extension InvestEnterAmountViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selectedPaymentToken = paymentBalances[indexPath.row]
        tableView.reloadData()
        recompute()
    }
}

// MARK: - Invest (Comprar) Flow - Screen 3

/// Screen 3: confirmation of the purchase (stage 1: stubbed execution).
final class InvestConfirmViewController: UIViewController {
    var onPurchase: (() -> Void)?

    private let draft: InvestBuyDraft

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stack = UIStackView()

    private let titleLabel = UILabel()

    private let whatTitleLabel = UILabel()
    private let whatValueLabel = UILabel()

    private let costTitleLabel = UILabel()
    private let costValueLabel = UILabel()

    private let qtyTitleLabel = UILabel()
    private let qtyValueLabel = UILabel()

    private let remainingTitleLabel = UILabel()
    private let remainingValueLabel = UILabel()

    private let buyButton = UIButton(type: .system)

    init(draft: InvestBuyDraft) {
        self.draft = draft
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .backgroundPrimary
        title = NSLocalizedString("ui_invertir_confirm_title", comment: "Invertir confirm title")
        configureLayout()
        configureValues()
    }

    private func configureLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 10
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24)
        ])

        titleLabel.setStyle(.title3)
        titleLabel.text = "Revisá tu compra"

        for label in [whatTitleLabel, costTitleLabel, qtyTitleLabel, remainingTitleLabel] {
            label.setStyle(.caption1Medium)
            label.textColor = .labelSecondary
        }
        whatTitleLabel.text = "Vas a comprar"
        costTitleLabel.text = "Costo"
        qtyTitleLabel.text = "Cantidad"
        remainingTitleLabel.text = "Te quedan en ahorros"

        for label in [whatValueLabel, costValueLabel, qtyValueLabel, remainingValueLabel] {
            label.setStyle(.title3)
            label.textColor = .labelPrimary
            label.numberOfLines = 0
        }

        buyButton.setText(NSLocalizedString("ui_invertir_buy_action", comment: "Invertir buy action"), .filled)
        buyButton.addTarget(self, action: #selector(didTapBuy), for: .touchUpInside)
        NSLayoutConstraint.activate([
            buyButton.heightAnchor.constraint(equalToConstant: 48)
        ])

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(spacer(18))

        stack.addArrangedSubview(whatTitleLabel)
        stack.addArrangedSubview(whatValueLabel)
        stack.addArrangedSubview(spacer(10))

        stack.addArrangedSubview(costTitleLabel)
        stack.addArrangedSubview(costValueLabel)
        stack.addArrangedSubview(spacer(10))

        stack.addArrangedSubview(qtyTitleLabel)
        stack.addArrangedSubview(qtyValueLabel)
        stack.addArrangedSubview(spacer(10))

        stack.addArrangedSubview(remainingTitleLabel)
        stack.addArrangedSubview(remainingValueLabel)
        stack.addArrangedSubview(spacer(20))

        stack.addArrangedSubview(buyButton)
    }

    private func spacer(_ height: CGFloat) -> UIView {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([v.heightAnchor.constraint(equalToConstant: height)])
        return v
    }

    private func configureValues() {
        whatValueLabel.text = draft.selectedToken.symbol
        costValueLabel.text = formatFiat(draft.investAmountFiat, code: draft.fiatCode)
        qtyValueLabel.text = "\(formatNumber5(draft.buyQuantity)) \(draft.selectedToken.symbol)"
        remainingValueLabel.text = formatFiat(draft.remainingSavingsFiat, code: draft.fiatCode)
    }

    @objc private func didTapBuy() {
        onPurchase?()
    }

    private func formatFiat(_ value: Double, code: String) -> String {
        let fiatString = String(format: "%.6f", max(0, value))
        return TokenBalance.displayCurrency(from: fiatString, code: code)
    }

    private func formatNumber5(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.autoupdatingCurrent
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 5
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.5f", value)
    }
}

// MARK: - Stage-1 execution stub screen

final class InvestPurchaseInProgressViewController: UIViewController {
    var onFinish: (() -> Void)?

    private let titleLabel = UILabel()
    private let button = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .backgroundPrimary
        title = NSLocalizedString("ui_invertir_buy_action", comment: "Invertir buy title")

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setStyle(.title3)
        titleLabel.textColor = .labelPrimary
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center
        titleLabel.text = "Compra en progreso"

        button.translatesAutoresizingMaskIntoConstraints = false
        button.setText(NSLocalizedString("ui_invertir_back_to_invertir_action", comment: "Invertir again action"), .filled)
        button.addTarget(self, action: #selector(didTapFinish), for: .touchUpInside)

        view.addSubview(titleLabel)
        view.addSubview(button)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -30),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            button.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            button.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            button.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    @objc private func didTapFinish() {
        onFinish?()
    }
}

// MARK: - Invest (Comprar) Flow - Coordinator

final class InvestBuyFlowCoordinator: NSObject, UIAdaptivePresentationControllerDelegate {
    private weak var presenter: UIViewController?
    private weak var navigationController: UINavigationController?
    private weak var enterAmountViewController: InvestEnterAmountViewController?

    private var paymentTotalFiat: Double = 0
    private var paymentBalances: [TokenBalance] = []
    private var balancesObserver: NSObjectProtocol?
    private var fallbackBalancesTask: URLSessionTask?
    private var fallbackMultiTasks: [URLSessionTask] = []
    var onDismiss: (() -> Void)?

    init(presenter: UIViewController) {
        self.presenter = presenter
    }

    func start() {
        let s1 = InvestSelectTokenViewController()
        s1.onLoadedBalances = { _ in
            // Markets list is provided by whitelist; payment balances are loaded separately.
        }
        s1.onTokenSelected = { [weak self] token, unitPrice in
            self?.showEnterAmount(selectedToken: token, unitPriceFiatPerToken: unitPrice)
        }

        let nav = UINavigationController(rootViewController: s1)
        nav.modalPresentationStyle = .pageSheet
        if #unavailable(iOS 15) {
            nav.navigationBar.backgroundColor = .backgroundSecondary
        }
        nav.presentationController?.delegate = self
        presenter?.present(nav, animated: true)
        navigationController = nav

        subscribeToBalances()
        applyFromCacheOrFetchIfNeeded()
    }

    private func showEnterAmount(selectedToken: TokenBalance, unitPriceFiatPerToken: Double?) {
        let fiatCode = AppSettings.selectedFiatCode
        let s2 = InvestEnterAmountViewController(selectedToken: selectedToken,
                                                 paymentTotalFiat: paymentTotalFiat,
                                                 fiatCode: fiatCode,
                                                 paymentBalances: paymentBalances,
                                                 unitPriceFiatPerToken: unitPriceFiatPerToken)
        enterAmountViewController = s2
        s2.onContinue = { [weak self] draft in
            self?.showConfirm(draft: draft)
        }
        navigationController?.pushViewController(s2, animated: true)
    }

    private func showConfirm(draft: InvestBuyDraft) {
        let s3 = InvestConfirmViewController(draft: draft)
        s3.onPurchase = { [weak self] in
            self?.createBuyTransactionRequest(draft: draft)
            self?.showInProgress()
        }
        navigationController?.pushViewController(s3, animated: true)
    }

    private func createBuyTransactionRequest(draft: InvestBuyDraft) {
        guard let selected = try? Safe.getSelected() else {
            LogService.shared.error("[TransactionRequests][buy] Missing selected Safe; cannot build vaultId")
            return
        }
        let vaultEvmAddress = selected.addressValue.checksummed

        let notes =
            "investAmountFiat=\(draft.investAmountFiat);" +
            " unitPriceFiatPerToken=\(draft.unitPriceFiatPerToken);" +
            " fiatCode=\(draft.fiatCode);" +
            " buyQuantity=\(draft.buyQuantity)"

        let payload = CreateTransactionRequestBody(
            transactionType: .buy,
            currency: draft.selectedToken.symbol,
            amount: max(0, draft.buyQuantity),
            requestStatus: .requested,
            destinationAddress: nil,
            notes: notes
        )

        let service = TransactionRequestsService(authRepository: App.shared.authRepository, logger: LogService.shared)
        service.createTransactionRequestForCurrentSession(
            vaultEvmAddress: vaultEvmAddress,
            chainId: selected.chain?.id,
            payload: payload
        ) { result in
            switch result {
            case .success:
                LogService.shared.info("[TransactionRequests][buy] created")
            case .failure(let error):
                LogService.shared.error("[TransactionRequests][buy] create FAILED", error: error)
            }
        }
    }

    private func showInProgress() {
        let vc = InvestPurchaseInProgressViewController()
        vc.onFinish = { [weak self] in
            self?.navigationController?.dismiss(animated: true) { [weak self] in
                self?.onDismiss?()
            }
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    private func subscribeToBalances() {
        if balancesObserver != nil { return }

        balancesObserver = NotificationCenter.default.addObserver(
            forName: .balanceUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let balances = notification.userInfo?["balances"] as? [TokenBalance] else { return }
            guard balances.contains(where: { $0.balanceValue.value > 0 }) else { return }

            LatestBalancesCache.shared.update(balances: balances)
            let payments = self.paymentBalancesFromAllBalances(balances)
            self.paymentBalances = payments
            self.paymentTotalFiat = payments.reduce(0) { $0 + $1.fiatValue }
            self.enterAmountViewController?.updatePaymentBalances(payments, totalFiat: self.paymentTotalFiat)
        }
    }

    private func applyFromCacheOrFetchIfNeeded() {
        let cached = LatestBalancesCache.shared.retrieve(chainId: nil) ?? []
        if !cached.isEmpty {
            let payments = paymentBalancesFromAllBalances(cached)
            paymentBalances = payments
            paymentTotalFiat = payments.reduce(0) { $0 + $1.fiatValue }
            enterAmountViewController?.updatePaymentBalances(payments, totalFiat: paymentTotalFiat)
            return
        }
        fetchBalancesForCache()
    }

    private func fetchBalancesForCache() {
        cancelFallbackLoads()
        if AppSettings.multiVaultBalancesEnabled {
            fetchMultiVaultBalancesForCache()
        } else {
            fetchSingleVaultBalancesForCache()
        }
    }

    private func fetchSingleVaultBalancesForCache() {
        guard let safe = try? Safe.getSelected(), let chain = safe.chain, let chainId = chain.id else { return }
        let service = chain.gatewayService()
        let query = "trusted=false&exclude_spam=true"
        fallbackBalancesTask = service.asyncBalances(safeAddress: safe.addressValue,
                                                    chainId: chainId,
                                                    query: query) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.fallbackBalancesTask = nil
                guard case .success(let summary) = result else { return }
                let balances = summary.items.map { TokenBalance($0, code: AppSettings.selectedFiatCode, chainId: chainId) }
                LatestBalancesCache.shared.update(balances: balances)
                let payments = self.paymentBalancesFromAllBalances(balances)
                self.paymentBalances = payments
                self.paymentTotalFiat = payments.reduce(0) { $0 + $1.fiatValue }
                self.enterAmountViewController?.updatePaymentBalances(payments, totalFiat: self.paymentTotalFiat)
            }
        }
    }

    private func fetchMultiVaultBalancesForCache() {
        guard let safes = try? Safe.getAll() else { return }
        let deployedSafes = safes.filter { $0.safeStatus == .deployed }
        if deployedSafes.isEmpty { return }

        let group = DispatchGroup()
        let syncQueue = DispatchQueue(label: "io.gnosis.multisig.investbuy.paymentbalances", qos: .userInitiated)
        var results: [(chainId: String, summary: SafeBalanceSummary)] = []

        for safe in deployedSafes {
            guard let chain = safe.chain, let chainId = chain.id else { continue }
            group.enter()
            let service = chain.gatewayService()
            let query = "trusted=false&exclude_spam=true"
            let task = service.asyncBalances(safeAddress: safe.addressValue,
                                             chainId: chainId,
                                             query: query) { [weak self] result in
                guard self != nil else { return }
                syncQueue.async {
                    if case .success(let summary) = result {
                        results.append((chainId: chainId, summary: summary))
                    }
                    group.leave()
                }
            }
            if let task {
                fallbackMultiTasks.append(task)
            } else {
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.fallbackMultiTasks.removeAll()
            guard !results.isEmpty else { return }
            let aggregated = MultiVaultBalancesAggregator.aggregate(results, fiatCode: AppSettings.selectedFiatCode)
            LatestBalancesCache.shared.update(balances: aggregated.balances)
            let payments = self.paymentBalancesFromAllBalances(aggregated.balances)
            self.paymentBalances = payments
            self.paymentTotalFiat = payments.reduce(0) { $0 + $1.fiatValue }
            self.enterAmountViewController?.updatePaymentBalances(payments, totalFiat: self.paymentTotalFiat)
        }
    }

    private func cancelFallbackLoads() {
        fallbackBalancesTask?.cancel()
        fallbackBalancesTask = nil
        fallbackMultiTasks.forEach { $0.cancel() }
        fallbackMultiTasks.removeAll()
    }

    private func paymentBalancesFromAllBalances(_ balances: [TokenBalance]) -> [TokenBalance] {
        let nonZero = balances.filter { $0.balanceValue.value > 0 }
        let filtered = nonZero.filter { item in
            let sectionId = TokenCategory.sectionId(for: item.category)
            return sectionId == TokenCategory.sectionUSD || sectionId == TokenCategory.sectionMoneyMarket
        }
        return filtered.sorted { lhs, rhs in
            func rank(_ item: TokenBalance) -> Int {
                TokenCategory.sectionId(for: item.category) == TokenCategory.sectionMoneyMarket ? 1 : 0
            }
            let lr = rank(lhs), rr = rank(rhs)
            if lr != rr { return lr < rr }
            if lhs.fiatValue != rhs.fiatValue { return lhs.fiatValue > rhs.fiatValue }
            return lhs.symbol.localizedCaseInsensitiveCompare(rhs.symbol) == .orderedAscending
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        if let observer = balancesObserver {
            NotificationCenter.default.removeObserver(observer)
            balancesObserver = nil
        }
        cancelFallbackLoads()
        onDismiss?()
    }
}
