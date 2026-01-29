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
    /// When true, we already successfully synced the whitelist but the backend returned an empty list.
    /// In that case, reloading would cause an infinite sync loop (empty local -> sync -> empty -> reload -> ...).
    private var didReceiveEmptyWhitelistFromBackend = false
    private var didAttemptWhitelistPricingBackfill = false
    private var allMarketItems: [TokenBalance] = []
    private var tokenPrices: [String: Double] = [:] // Cache: token address -> unit price
    private var tokenChangePct24h: [String: Double] = [:] // Cache: token address -> 24h % change
    private var marketPriceTasks: [URLSessionTask] = []
    private let marketPriceService = MarketPriceService()
    private var isMarketPriceLoadInProgress: Bool = false

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

    }
    
    override var isEmpty: Bool {
        return super.isEmpty
    }

    // MARK: - Section ordering (Invertir)

    // Invertir "markets" rows are not chain-specific; show money-market yield using Ethereum as default.
    override var useEthereumUnderlyingApyForMoneyMarket: Bool { true }

    override var balanceSectionOrder: [(id: String, title: String)] {
        [
            (id: TokenCategory.sectionMoneyMarket, title: "Money market"),
            (id: TokenCategory.sectionAcciones, title: "Acciones"),
            (id: TokenCategory.sectionEtfIndices, title: "ETF de indices"),
            (id: TokenCategory.sectionEtfOtros, title: "ETF otros"),
            (id: TokenCategory.sectionCripto, title: "Cripto"),
            (id: TokenCategory.sectionOro, title: "Oro"),
            // Keep these last so we don't hide anything unexpected.
            (id: TokenCategory.sectionOtros, title: "Otros"),
            (id: TokenCategory.sectionBlackToken, title: "blackToken")
        ]
    }

    override func mapCategoryToSectionId(_ item: TokenBalance) -> String {
        TokenCategory.sectionId(for: item.category)
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
            if didReceiveEmptyWhitelistFromBackend {
                LogService.shared.error("[InvertirMarkets] Whitelist is empty after a successful sync; stopping auto-sync to avoid infinite loop")
                // Show empty state without overwriting global balances header/actions.
                apply(rawItems: [],
                      displayItems: [],
                      totalFiat: nil,
                      transferSelectableAssets: nil,
                      postBalanceUpdated: false)
                endRefreshing()
                return
            }
            isWhitelistSyncInProgress = true
            LogService.shared.debug("[InvertirMarkets] Whitelist empty locally; triggering sync (chainId=\(chainId), network=\(network ?? "nil"))")
            App.shared.tokenWhitelistRepository.syncWhitelist(force: false, network: nil) { [weak self] result in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.isWhitelistSyncInProgress = false
                    switch result {
                    case .success:
                        // If backend returns an empty list, do not reload forever.
                        let newTotal = TokenWhitelist.all.count
                        if newTotal == 0 {
                            self.didReceiveEmptyWhitelistFromBackend = true
                            LogService.shared.error("[InvertirMarkets] Whitelist sync completed but still empty; showing empty state")
                        } else {
                            self.didReceiveEmptyWhitelistFromBackend = false
                            LogService.shared.debug("[InvertirMarkets] Whitelist sync completed; loading markets (localCount=\(newTotal))")
                        }
                        // Avoid `reloadData()` here to prevent re-entering the sync branch in a loop.
                        self.loadTokenItems()
                    case .failure(let error):
                        // Allow retry on next reload / pull-to-refresh.
                        self.didReceiveEmptyWhitelistFromBackend = false
                        LogService.shared.error("[InvertirMarkets] Whitelist sync failed: \(error.localizedDescription)")
                        // Show empty state without overwriting global balances header/actions.
                        self.apply(rawItems: [],
                                   displayItems: [],
                                   totalFiat: nil,
                                   transferSelectableAssets: nil,
                                   postBalanceUpdated: false)
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

        let balances = entries.map { TokenBalance(whitelist: $0, fiatCode: "USD") }
        let filteredBalances = balances.filter { !TokenCategory.isSavings($0.category) }

        do {
            let sample = filteredBalances.prefix(20).map {
                "\($0.symbol){name=\($0.name), cat=\($0.category), addr=\($0.address.prefix(8))}"
            }.joined(separator: ", ")
            let catCounts = Dictionary(grouping: filteredBalances) { $0.category.lowercased() }
                .mapValues { $0.count }
                .sorted { $0.value > $1.value }
                .prefix(12)
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ", ")

            LogService.shared.debug("[InvertirMarkets] balanceBuilt count=\(filteredBalances.count) categories{\(catCounts)} sample[\(min(filteredBalances.count, 20))]=[\(sample)]")
        }

        allMarketItems = filteredBalances

        apply(items: allMarketItems,
              totalFiat: TokenBalance.displayCurrency(from: "0", code: AppSettings.selectedFiatCode))

        // Fetch prices
        let shownEntries = entries.filter { !TokenCategory.isSavings($0.tokenCategory) }
        fetchPricesForMarketTokens(entries: shownEntries)
    }

    private func apply(items: [TokenBalance], totalFiat: String?) {
        apply(rawItems: items,
              displayItems: items,
              totalFiat: totalFiat,
              transferSelectableAssets: nil,
              postBalanceUpdated: false)
    }

    private func fetchPricesForMarketTokens(entries: [TokenWhitelist]) {
        guard !isMarketPriceLoadInProgress else {
            LogService.shared.debug("[InvertirPrices] fetchPrices skipped; a fetch is already in progress")
            return
        }
        isMarketPriceLoadInProgress = true

        marketPriceTasks.forEach { $0.cancel() }
        marketPriceTasks = []

        LogService.shared.debug("[InvertirPrices][START] Fetching market prices; count=\(entries.count)")
        marketPriceTasks = marketPriceService.fetchPrices(entries: entries) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isMarketPriceLoadInProgress = false
                switch result {
                case .success(let snapshot):
                    LogService.shared.debug("[InvertirPrices][DONE] Loaded market prices count=\(snapshot.pricesByAddress.count) at=\(snapshot.fetchedAt)")
                    self.tokenPrices = snapshot.pricesByAddress
                    self.tokenChangePct24h = snapshot.changePct24hByAddress
                    self.logPriceBindingDiagnostics()
                    self.tableView.reloadData()
                case .failure(let error):
                    LogService.shared.error("[InvertirPrices][FAIL] Market price fetch error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func logPriceBindingDiagnostics() {
        let mapped = allMarketItems.filter { tokenPrices[$0.address] != nil }.count
        let unmapped = allMarketItems.count - mapped
        let sampleUnmapped = allMarketItems
            .filter { tokenPrices[$0.address] == nil }
            .prefix(12)
            .map { "\($0.symbol){addr=\($0.address.prefix(8))}" }
            .joined(separator: ", ")
        LogService.shared.debug("[InvertirPrices][DIAG] cellUpdateReady mapped=\(mapped) unmapped=\(unmapped) sampleUnmapped[\(min(unmapped, 12))]=[\(sampleUnmapped)]")
    }

    private func logWhitelistPricingSummary(prefix: String, entries: [TokenWhitelist]) {
        let onlyOndoBond = entries.filter {
            ($0.priceSource ?? "").lowercased() == "ondobond" && ($0.priceSourceParam ?? "").isEmpty
        }.count
        let ondoBondWithParam = entries.filter {
            ($0.priceSource ?? "").lowercased() == "ondobond" && !($0.priceSourceParam ?? "").isEmpty
        }.count
        let onlyKraken = entries.filter {
            ($0.priceSource ?? "").lowercased() == "kraken" && ($0.priceSourceParam ?? "").isEmpty
        }.count
        let krakenWithParam = entries.filter {
            ($0.priceSource ?? "").lowercased() == "kraken" && !($0.priceSourceParam ?? "").isEmpty
        }.count
        let empty = entries.filter { ($0.priceSource ?? "").isEmpty }.count
        let other = entries.count - onlyOndoBond - ondoBondWithParam - onlyKraken - krakenWithParam - empty

        LogService.shared.debug("\(prefix) priceSource ondoBond(noParam=\(onlyOndoBond), withParam=\(ondoBondWithParam)) kraken(noParam=\(onlyKraken), withParam=\(krakenWithParam)) empty=\(empty) other=\(other)")
    }

    // MARK: - Cell Configuration with Price
    
    /// Configures the badge and also sets the price for InvertirBalanceTableViewCell
    override func configureBadge(for cell: BalanceTableViewCell, item: TokenBalance, section: BalanceCategorySection) {
        // Configure price and description for InvertirBalanceTableViewCell
        if let invertirCell = cell as? InvertirBalanceTableViewCell {
            invertirCell.setDescription(item.name)
            // In the Money Market section we only want to show the APY badge.
            // Hide price text for those rows.
            if section.id == "moneymarket" {
                invertirCell.setPrice(nil)
            } else {
                let priceText = formatTokenPrice(item)
                invertirCell.setPrice(priceText)
            }
        }
        
        // Call parent's badge configuration
        super.configureBadge(for: cell, item: item, section: section)

        // Override badge for Invertir: show 24h % change instead of yield
        if [
            TokenCategory.sectionAcciones,
            TokenCategory.sectionEtfIndices,
            TokenCategory.sectionEtfOtros,
            TokenCategory.sectionCripto,
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
        } else if section.id != "moneymarket" {
            cell.setBadge(text: nil)
        }
    }

    private func formatTokenPrice(_ token: TokenBalance) -> String? {
        guard let price = tokenPrices[token.address], price > 0 else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.autoupdatingCurrent
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let formattedValue = formatter.string(from: NSNumber(value: price)) ?? String(format: "%.2f", price)
        let code = AppSettings.selectedFiatCode
        return "\(formattedValue) \(code)"
    }

    private func formatChangePct(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "-"
        let absValue = abs(value)
        let formatted = String(format: "%.2f", absValue)
        return "\(sign)\(formatted)%"
    }
}

 
