//
//  InvertirBalancesViewController.swift
//  Multisig
//
//  Created by Assistant on 12/18/25.
//

import UIKit
import SwiftCryptoTokenFormatter

/// Balances list for the Invertir tab with fiat value and amount hidden.
class InvertirBalancesViewController: BalancesViewController {
    private var isWhitelistSyncInProgress = false
    private var didAttemptWhitelistPricingBackfill = false
    private var allMarketItems: [TokenBalance] = []
    private var tokenPrices: [String: Double] = [:] // Cache: token address -> unit price
    private var marketPriceTasks: [URLSessionTask] = []
    private let marketPriceService = MarketPriceService()
    private var isMarketPriceLoadInProgress: Bool = false

    // Bottom-sticky search UI
    private let searchContainerView = UIView()
    private let searchFieldBackgroundView = UIView()
    private let searchTextField = UITextField()
    private var searchBottomConstraint: NSLayoutConstraint?
    private let searchContainerHeight: CGFloat = 64
    private var searchTerm: String = ""

    override func viewDidLoad() {
        hideFiatAndAmount = true
        super.viewDidLoad()

        LogService.shared.debug("[InvertirMarkets][BOOT] viewDidLoad vc=\(String(describing: type(of: self)))")
        
        // IMPORTANT: keep using BalancesViewController's logic, but swap the cell XIB
        // so `BalanceTableViewCell` dequeues our Invertir-specific layout.
        tableView.register(
            UINib(nibName: "InvertirBalanceTableViewCell", bundle: nil),
            forCellReuseIdentifier: "BalanceTableViewCell"
        )

        configureBottomSearch()
    }

    // MARK: - Section ordering (Invertir)

    // Invertir “markets” rows are not chain-specific; show money-market yield using Ethereum as default.
    override var useEthereumUnderlyingApyForMoneyMarket: Bool { true }

    override var balanceSectionOrder: [(id: String, title: String)] {
        [
            (id: "moneymarket", title: "Money market"),
            (id: "cripto", title: "Cripto"),
            (id: "gold", title: "Oro"),
            (id: "invest", title: "ETF y acciones"),
            // Keep these last so we don't hide anything unexpected.
            (id: "otros", title: "Otros"),
            (id: "blacktoken", title: "blackToken")
        ]
    }

    override func mapCategoryToSectionId(_ item: TokenBalance) -> String {
        switch item.category.lowercased() {
        case "moneymarket":
            return "moneymarket"
        case "token", "cripto":
            return "cripto"
        case "oro", "gold":
            return "gold"
        case "invest":
            return "invest"
        case "blacktoken":
            return "blacktoken"
        default:
            return "otros"
        }
    }

    override func loadTokenItems() {
        guard let safe = try? Safe.getSelected(), let chain = safe.chain else {
            // Markets screen: don't overwrite global balances UI when we don't have real balances.
            apply(rawItems: [],
                  displayItems: [],
                  totalFiat: nil,
                  transferSelectableAssets: nil,
                  postBalanceUpdated: false)
            return
        }

        let chainId = chain.id ?? ""
        let network = chain.shortName
        let totalWhitelist = TokenWhitelist.all.count
        
        LogService.shared.debug("[InvertirMarkets][BOOT] loadTokenItems safe=\(safe.address ?? "nil") chainId=\(chainId) network=\(network ?? "nil") totalWhitelistLocal=\(totalWhitelist)")
        LogService.shared.debug("[InvertirMarkets][BOOT] Providers ondoBase=\(ApiConfig.ondoAppBaseURL.absoluteString) krakenBase=\(ApiConfig.krakenPublicBaseURL.absoluteString)")

        do {
            let all = TokenWhitelist.all
            let enabledFalse = all.filter { $0.enabled == false }.count
            let enabledNil = all.filter { $0.enabled == nil }.count
            let missingChainId = all.filter { (($0.chainId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)).isEmpty }.count
            let missingNetwork = all.filter { (($0.network ?? "").trimmingCharacters(in: .whitespacesAndNewlines)).isEmpty }.count
            let uniqueSymbols = Set(all.compactMap { ($0.tokenSymbol ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }.filter { !$0.isEmpty }).count
            LogService.shared.debug("[InvertirMarkets] rawWhitelist total=\(all.count) uniqueSymbols=\(uniqueSymbols) enabledFalse=\(enabledFalse) enabledNil=\(enabledNil) missing(chainId=\(missingChainId), network=\(missingNetwork)) chainId=\(chainId) network=\(network ?? "nil")")
        }

        if totalWhitelist == 0, !isWhitelistSyncInProgress {
            isWhitelistSyncInProgress = true
            LogService.shared.debug("[InvertirMarkets] Whitelist empty locally; triggering sync (chainId=\(chainId), network=\(network ?? "nil"))")
            App.shared.tokenWhitelistRepository.syncWhitelist(force: false, network: nil) { [weak self] result in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.isWhitelistSyncInProgress = false
                    switch result {
                    case .success:
                        LogService.shared.debug("[InvertirMarkets] Whitelist sync completed; reloading markets")
                        self.reloadData()
                    case .failure(let error):
                        LogService.shared.error("[InvertirMarkets] Whitelist sync failed: \(error.localizedDescription)")
                        self.apply(items: [], totalFiat: TokenBalance.displayCurrency(from: "0", code: AppSettings.selectedFiatCode))
                    }
                }
            }
            return
        }

        let entries = TokenWhitelist.markets(chainId: chainId, network: network)

        do {
            self.logWhitelistPricingSummary(prefix: "[InvertirMarkets][WL]", entries: entries)
            let sample = entries.prefix(20).map {
                let sym = ($0.tokenSymbol ?? "nil")
                let cat = ($0.tokenCategory ?? "nil")
                let cid = ($0.chainId ?? "nil")
                let net = ($0.network ?? "nil")
                let en = String(describing: $0.enabled)
                return "\(sym){cat=\(cat),chainId=\(cid),net=\(net),enabled=\(en)}"
            }.joined(separator: ", ")

            let catCounts = Dictionary(grouping: entries) { ($0.tokenCategory ?? "nil").lowercased() }
                .mapValues { $0.count }
                .sorted { $0.value > $1.value }
                .prefix(12)
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ", ")

            LogService.shared.debug("[InvertirMarkets] afterMarkets grouped=\(entries.count) categories{\(catCounts)} sample[\(min(entries.count, 20))]=[\(sample)]")
        }

        // If the app already has a whitelist but none of the entries have priceSource, we likely
        // need a backfill sync (older local data or backend key mismatch). Attempt this once.
        let hasAnyPriceSource = entries.contains { !((($0.priceSource ?? "").trimmingCharacters(in: .whitespacesAndNewlines))).isEmpty }
        if !entries.isEmpty, !hasAnyPriceSource, !isWhitelistSyncInProgress, !didAttemptWhitelistPricingBackfill {
            didAttemptWhitelistPricingBackfill = true
            isWhitelistSyncInProgress = true
            LogService.shared.debug("[InvertirMarkets] Detected empty priceSource for all market entries; triggering whitelist backfill sync")
            App.shared.tokenWhitelistRepository.syncWhitelist(force: true, network: nil) { [weak self] result in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.isWhitelistSyncInProgress = false
                    switch result {
                    case .success:
                        LogService.shared.debug("[InvertirMarkets] Whitelist backfill sync completed; reloading markets")
                        self.reloadData()
                    case .failure(let error):
                        LogService.shared.error("[InvertirMarkets] Whitelist backfill sync failed: \(error.localizedDescription)")
                        // Continue showing tokens (without prices) even if backfill fails.
                        self.apply(items: self.filteredItems(from: self.allMarketItems, term: self.searchTerm),
                                   totalFiat: TokenBalance.displayCurrency(from: "0", code: AppSettings.selectedFiatCode))
                    }
                }
            }
            return
        }

        var shownEntries: [TokenWhitelist] = []
        var items: [TokenBalance] = []
        items.reserveCapacity(entries.count)
        shownEntries.reserveCapacity(entries.count)

        for entry in entries {
            let category = (entry.tokenCategory ?? "").lowercased()
            if ["stablecoin", "stablecoins", "savings"].contains(category) {
                continue
            }
            shownEntries.append(entry)
            // Markets list uses USD-only pricing display.
            items.append(TokenBalance(whitelist: entry, fiatCode: "USD"))
        }

        items.sort { lhs, rhs in
            let sym = lhs.symbol.localizedCaseInsensitiveCompare(rhs.symbol)
            if sym != .orderedSame { return sym == .orderedAscending }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        LogService.shared.debug("[InvertirMarkets] final shown=\(items.count) (filteredSavings=\(entries.count - items.count)) chainId=\(chainId) network=\(network ?? "nil")")
        allMarketItems = items
        fetchPricesForMarketTokens(entries: shownEntries)

        let filtered = filteredItems(from: items, term: searchTerm)
        let cachedBalances = LatestBalancesCache.shared.balances
        if cachedBalances.isEmpty {
            // If we don't have real balances yet (e.g. user opened Invertir first),
            // don't publish a fake "0" total that would overwrite the header.
            apply(rawItems: [],
                  displayItems: filtered,
                  totalFiat: nil,
                  transferSelectableAssets: nil,
                  postBalanceUpdated: false)
        } else {
            let total = cachedBalances.reduce(0.0) { $0 + $1.fiatValue }
            let totalFiat = TokenBalance.displayCurrency(from: String(total), code: AppSettings.selectedFiatCode)
            // Publish real balances for header/actions, but show market rows in the table.
            apply(rawItems: cachedBalances,
                  displayItems: filtered,
                  totalFiat: totalFiat,
                  transferSelectableAssets: nil,
                  postBalanceUpdated: true)
        }
    }
    
    // MARK: - Price Fetching
    
    private func fetchPricesForMarketTokens(entries: [TokenWhitelist]) {
        // Cancel any existing price fetch
        marketPriceTasks.forEach { $0.cancel() }
        marketPriceTasks = []
        isMarketPriceLoadInProgress = !entries.isEmpty

        LogService.shared.debug("[InvertirPrices][START] entries=\(entries.count) ondoBase=\(ApiConfig.ondoAppBaseURL.absoluteString) krakenBase=\(ApiConfig.krakenPublicBaseURL.absoluteString)")
        self.logWhitelistPricingSummary(prefix: "[InvertirPrices][INPUT]", entries: entries)

        marketPriceTasks = marketPriceService.fetchPrices(entries: entries) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isMarketPriceLoadInProgress = false
                switch result {
                case .success(let snapshot):
                    LogService.shared.debug("[InvertirPrices][DONE] Loaded market prices count=\(snapshot.pricesByAddress.count) at=\(snapshot.fetchedAt)")
                    self.tokenPrices = snapshot.pricesByAddress
                    self.logPriceBindingDiagnostics()
                    self.tableView.reloadData()
                case .failure(let error):
                    LogService.shared.error("[InvertirPrices][FAIL] Failed to fetch market prices", error: error)
                }
                // If the user pulled to refresh, keep the spinner until prices are ready (matches Assets behavior).
                self.endRefreshing()
            }
        }
    }

    /// Keep pull-to-refresh active until market prices load, otherwise the UI ends refresh quickly
    /// and then "jumps" when prices arrive (can feel like a stutter/vibration).
    override func endRefreshing() {
        guard !isMarketPriceLoadInProgress else { return }
        super.endRefreshing()
    }
    
    private func logWhitelistPricingSummary(prefix: String, entries: [TokenWhitelist]) {
        // Summarize how many entries have a pricing source configured.
        let normalizedSource: (TokenWhitelist) -> String = { e in
            (e.priceSource ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        let hasParam: (TokenWhitelist) -> Bool = { e in
            !((e.priceSourceParam ?? "").trimmingCharacters(in: .whitespacesAndNewlines)).isEmpty
        }
        let hasAddr: (TokenWhitelist) -> Bool = { e in
            let a = (e.networkAddress ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !a.isEmpty
        }
        
        let countsBySource = Dictionary(grouping: entries, by: normalizedSource)
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
            .map { "\($0.key.isEmpty ? "<empty>" : $0.key)=\($0.value)" }
            .joined(separator: ", ")
        
        let emptySourceCount = entries.filter { normalizedSource($0).isEmpty }.count
        let missingParamCount = entries.filter { !normalizedSource($0).isEmpty && !hasParam($0) }.count
        let missingAddrCount = entries.filter { !hasAddr($0) }.count
        
        LogService.shared.debug("\(prefix) total=\(entries.count) sources{\(countsBySource)} emptySource=\(emptySourceCount) missingParam=\(missingParamCount) missingAddr=\(missingAddrCount)")
        
        // Print a small sample of pricing-critical fields.
        let sample = entries.prefix(15).map { e -> String in
            let sym = (e.tokenSymbol ?? "nil").trimmingCharacters(in: .whitespacesAndNewlines)
            let addr = (e.networkAddress ?? "nil").trimmingCharacters(in: .whitespacesAndNewlines)
            let src = normalizedSource(e)
            let param = (e.priceSourceParam ?? "nil").trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(sym){src=\(src.isEmpty ? "<empty>" : src),param=\(param),addr=\(addr)}"
        }.joined(separator: ", ")
        LogService.shared.debug("\(prefix) sample[\(min(entries.count, 15))]=[\(sample)]")
    }
    
    private func logPriceBindingDiagnostics() {
        let items = allMarketItems
        let priceKeys = Set(tokenPrices.keys)
        let itemKeys = Set(items.map { $0.address })
        
        let withPrice = items.filter { tokenPrices[$0.address] != nil }.count
        let missingPrice = items.count - withPrice
        let extraPriceKeys = priceKeys.subtracting(itemKeys)
        let missingPriceKeys = itemKeys.subtracting(priceKeys)
        
        LogService.shared.debug("[InvertirPrices][BIND] items=\(items.count) priced=\(withPrice) missing=\(missingPrice) tokenPricesKeys=\(priceKeys.count) extraKeys=\(extraPriceKeys.count) missingKeys=\(missingPriceKeys.count)")
        
        // Show a few misses to spot systematic mismatches (address casing, native token address, etc.).
        let missSample = items.filter { tokenPrices[$0.address] == nil }.prefix(12).map { "\($0.symbol){addr=\($0.address)}" }.joined(separator: ", ")
        LogService.shared.debug("[InvertirPrices][BIND] missingSample[\(min(missingPrice, 12))]=[\(missSample)]")
        
        let priceSample = items.filter { tokenPrices[$0.address] != nil }.prefix(12).map { item in
            let p = tokenPrices[item.address] ?? 0
            return "\(item.symbol){addr=\(item.address),p=\(p)}"
        }.joined(separator: ", ")
        LogService.shared.debug("[InvertirPrices][BIND] pricedSample[\(min(withPrice, 12))]=[\(priceSample)]")
    }

    // MARK: - Search

    private func configureBottomSearch() {
        searchContainerView.translatesAutoresizingMaskIntoConstraints = false
        searchContainerView.backgroundColor = .backgroundPrimary

        searchFieldBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        searchFieldBackgroundView.backgroundColor = .backgroundSecondary
        searchFieldBackgroundView.layer.cornerRadius = 12
        searchFieldBackgroundView.layer.masksToBounds = true
        searchFieldBackgroundView.layer.borderWidth = 1
        searchFieldBackgroundView.layer.borderColor = UIColor.border.cgColor

        searchTextField.translatesAutoresizingMaskIntoConstraints = false
        searchTextField.borderStyle = .none
        searchTextField.setStyle(.bodyPrimary)
        searchTextField.clearButtonMode = .whileEditing
        searchTextField.autocorrectionType = .no
        searchTextField.autocapitalizationType = .none
        searchTextField.returnKeyType = .done
        searchTextField.addTarget(self, action: #selector(searchTextDidChange), for: .editingChanged)

        // Left icon
        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        icon.tintColor = .labelSecondary
        icon.contentMode = .scaleAspectFit
        icon.frame = CGRect(x: 0, y: 0, width: 18, height: 18)
        let iconContainer = UIView(frame: CGRect(x: 0, y: 0, width: 34, height: 18))
        icon.center = CGPoint(x: 17, y: 9)
        iconContainer.addSubview(icon)
        searchTextField.leftView = iconContainer
        searchTextField.leftViewMode = .always

        searchTextField.attributedPlaceholder = NSAttributedString(
            string: "Search tokens",
            attributes: GNOTextStyle.bodyTertiary.attributes
        )

        view.addSubview(searchContainerView)
        searchContainerView.addSubview(searchFieldBackgroundView)
        searchFieldBackgroundView.addSubview(searchTextField)

        let bottom = searchContainerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        searchBottomConstraint = bottom

        NSLayoutConstraint.activate([
            searchContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottom,
            searchContainerView.heightAnchor.constraint(equalToConstant: searchContainerHeight),

            searchFieldBackgroundView.leadingAnchor.constraint(equalTo: searchContainerView.leadingAnchor, constant: 16),
            searchFieldBackgroundView.trailingAnchor.constraint(equalTo: searchContainerView.trailingAnchor, constant: -16),
            searchFieldBackgroundView.topAnchor.constraint(equalTo: searchContainerView.topAnchor, constant: 10),
            searchFieldBackgroundView.bottomAnchor.constraint(equalTo: searchContainerView.bottomAnchor, constant: -10),

            searchTextField.leadingAnchor.constraint(equalTo: searchFieldBackgroundView.leadingAnchor, constant: 12),
            searchTextField.trailingAnchor.constraint(equalTo: searchFieldBackgroundView.trailingAnchor, constant: -12),
            searchTextField.topAnchor.constraint(equalTo: searchFieldBackgroundView.topAnchor, constant: 8),
            searchTextField.bottomAnchor.constraint(equalTo: searchFieldBackgroundView.bottomAnchor, constant: -8)
        ])

        // Ensure table content is not hidden behind the sticky search.
        let inset = searchContainerHeight + 8
        tableView.contentInset.bottom += inset
        tableView.scrollIndicatorInsets.bottom += inset

        // Move search bar above keyboard
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillShow(_:)),
                                               name: UIResponder.keyboardWillShowNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillHide(_:)),
                                               name: UIResponder.keyboardWillHideNotification,
                                               object: nil)

        // Dismiss keyboard when scrolling/tapping list
        tableView.keyboardDismissMode = .onDrag
    }

    @objc private func searchTextDidChange() {
        searchTerm = (searchTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        apply(items: filteredItems(from: allMarketItems, term: searchTerm),
              totalFiat: TokenBalance.displayCurrency(from: "0", code: AppSettings.selectedFiatCode))
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

    @objc private func keyboardWillShow(_ notification: NSNotification) {
        guard let view = view,
              let screenValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber
        else { return }
        let keyboardScreen = screenValue.cgRectValue
        let keyboardFrame = view.convert(keyboardScreen, from: UIScreen.main.coordinateSpace)
        let overlap = max(0, keyboardFrame.height - view.safeAreaInsets.bottom)
        searchBottomConstraint?.constant = -overlap
        UIView.animate(withDuration: duration.doubleValue) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func keyboardWillHide(_ notification: NSNotification) {
        guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber else { return }
        searchBottomConstraint?.constant = 0
        UIView.animate(withDuration: duration.doubleValue) {
            self.view.layoutIfNeeded()
        }
    }
    
    
    // MARK: - Cell Configuration with Price
    
    /// Configures the badge and also sets the price for InvertirBalanceTableViewCell
    override func configureBadge(for cell: BalanceTableViewCell, item: TokenBalance, section: BalanceCategorySection) {
        // Configure price and description for InvertirBalanceTableViewCell
        if let invertirCell = cell as? InvertirBalanceTableViewCell {
            let priceText = formatTokenPrice(item)
            invertirCell.setPrice(priceText)
            invertirCell.setDescription(item.name)
        }
        
        // Call parent's badge configuration
        super.configureBadge(for: cell, item: item, section: section)
        
        // Then apply Invertir-specific badge logic (non-money-market sections only).
        // Money market badges are handled by the base controller (live APY from Aave).
        if ["cripto", "invest", "gold"].contains(section.id) {
            let firstChar = item.symbol.uppercased().first
            let isAscending = firstChar.map { $0 >= "A" && $0 <= "M" } ?? false
            let triangle = isAscending ? "▲" : "▼"
            let color: UIColor = isAscending ? .success : .error
            let text = isAscending ? "5%" : "3%"
            cell.setBadge(text: text,
                          backgroundColor: .clear,
                          textColor: color,
                          prefix: triangle,
                          prefixColor: color)
        } else if section.id != "moneymarket" {
            cell.setBadge(text: nil)
        }
    }
    
    // MARK: - Price Formatting
    
    private func formatTokenPrice(_ item: TokenBalance) -> String? {
        guard let price = tokenPrices[item.address], price > 0 else {
            return "—"
        }
        return formatPrice(price, code: "USD")
    }
    
    private func decimalValue(from amount: BigDecimal) -> Double {
        // Convert BigDecimal to Decimal string without grouping, then to Double.
        let decimalString = TokenFormatter().string(from: amount,
                                                    decimalSeparator: ".",
                                                    thousandSeparator: "")
        guard let dec = Decimal(string: decimalString) else { return 0 }
        return (dec as NSDecimalNumber).doubleValue
    }
    
    private func formatPrice(_ value: Double, code: String) -> String {
        // Format price similar to how fiat values are displayed
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.autoupdatingCurrent
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        
        let formattedValue = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
        return "\(formattedValue) \(code)"
    }
}

