//
//  BalancesViewController.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 22.10.20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import UIKit
import CoreData
import Ethereum
import Solidity

// Loads and displays balances
class BalancesViewController: LoadableViewController, UITableViewDelegate, UITableViewDataSource {

    struct BalanceCategorySection {
        let id: String
        let title: String
        let items: [TokenBalance]
    }

    private enum Section {
        case importKeyBanner
        case passcodeBanner
        case balances(section: BalanceCategorySection)
    }
    var clientGatewayService: BalancesAPI {
        guard let chain = try? Safe.getSelected()?.chain else {
            return App.shared.clientGatewayService
        }
        return chain.gatewayService()
    }
    var remoteConfig: FirebaseRemoteConfig = FirebaseRemoteConfig.shared
    var createPasscodeFlow: CreatePasscodeFlow!

    override var isEmpty: Bool {
        let balances = allBalances(in: sections)
        return isEmptyAccount(items: balances)
    }

    private var currentDataTask: URLSessionTask?
    private var currentDataTasks: [URLSessionTask] = []

    private var sections: [Section] = []

    /// Latest raw balance summaries keyed by chainId (and potentially repeated per chain for multiple safes).
    /// Used to build per-network breakdowns in TokenDetail.
    private var latestBalanceInputs: [(chainId: String, summary: SafeBalanceSummary)] = []

    // MARK: - Money market (Aave) yield

    private let moneyMarketYieldService = MoneyMarketYieldService()
    private let savingsYieldService = SavingsYieldService()
    private let marketCapPricesService = MarketCapPricesService(
        authRepository: App.shared.authRepository,
        logger: LogService.shared
    )
    /// Lowercased aToken address -> APY percent (e.g. 3.25 == 3.25%).
    private var moneyMarketApyByTokenAddress: [String: Double] = [:]
    /// Display-symbol key (lowercased) -> APY display data (single or range).
    private var moneyMarketApyDisplayBySymbolKey: [String: MoneyMarketApyDisplay] = [:]
    /// Monotonically increasing token to ignore stale async updates.
    private var moneyMarketYieldGeneration: Int = 0

    /// Some lists (e.g. Invertir “markets”) do not have balances tied to a single chain.
    /// Those should use Ethereum (chainId=1) as the default yield source.
    /// Subclasses can override.
    var useEthereumUnderlyingApyForMoneyMarket: Bool { false }

    // MARK: - Savings (Ethereum default) yield

    /// Underlying symbol uppercased (e.g. "USDC") -> Ethereum APY percent (e.g. 3.25).
    private var savingsEthApyByUnderlyingSymbolUpper: [String: Double] = [:]
    private var savingsYieldGeneration: Int = 0

    private struct MoneyMarketApyDisplay {
        let minPercent: Double
        let maxPercent: Double
        let networkCount: Int
    }

    /// When true, we already tried a one-time forced whitelist sync to backfill newly added fields (e.g. wrapLabel).

    /// When true, hides fiat value and token amount in cells while keeping badge visible.
    var hideFiatAndAmount: Bool = false

    private let tableBackgroundColor: UIColor = .backgroundPrimary

    private var shouldShowImportKeyBanner: Bool {
        importKeyBannerWasShown != true && !shouldShowSafeTokenBanner
    }

    private var importKeyBannerWasShown: Bool? {
        get { AppSettings.importKeyBannerWasShown }
        set { AppSettings.importKeyBannerWasShown = newValue }
    }

    private var shouldShowPasscodeBanner: Bool {
        OwnerKeyController.hasPrivateKey && AppSettings.shouldOfferToSetupPasscode && !shouldShowSafeTokenBanner
    }

    private var shouldShowSafeTokenBanner: Bool {
        guard let safe = try? Safe.getSelected() else {
            return false
        }
        return safeTokenBannerWasShown != true && ClaimingAppController.isAvailable(chain: safe.chain!)
    }

    private var safeTokenBannerWasShown: Bool? {
        get { AppSettings.safeTokenBannerWasShown }
        set { AppSettings.safeTokenBannerWasShown = newValue }
    }

    convenience init() {
        self.init(namedClass: Self.superclass())
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.registerCell(BalanceTableViewCell.self)
        tableView.registerCell(BannerTableViewCell.self)
        tableView.registerHeaderFooterView(BasicHeaderView.self)

        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.backgroundColor = tableBackgroundColor
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }

        tableView.delegate = self
        tableView.dataSource = self

        if importKeyBannerWasShown != true && OwnerKeyController.hasPrivateKey {
            importKeyBannerWasShown = true
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(ownerKeyImported), name: .ownerKeyImported, object: nil)

        NotificationCenter.default.addObserver(
            self, selector: #selector(updatePasscodeBanner), name: .passcodeCreated, object: nil)

        NotificationCenter.default.addObserver(
            self, selector: #selector(lazyReloadData), name: .selectedFiatCurrencyChanged, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(lazyReloadData), name: .chainInfoChanged, object: nil)
        
        // update the balances for the case when collectibles were shown and this controller was off screen.
        NotificationCenter.default.addObserver(
            self, selector: #selector(doReloadData), name: .selectedSafeChanged, object: nil)

        recreateSectionsWithCurrentItems()
    }
    
    @objc private func doReloadData() {
        guard (try? Safe.getSelected())?.safeStatus == .deployed else { return }
        reloadData()
    }

    @objc private func ownerKeyImported() {
        importKeyBannerWasShown = true
        recreateSectionsWithCurrentItems()
    }

    @objc private func updatePasscodeBanner() {
        recreateSectionsWithCurrentItems()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Tracker.trackEvent(.assetsCoins)
    }

    /// Loads token items for this controller.
    /// - Note: Subclasses may override to provide non-gateway sources (e.g. markets/whitelist).
    func loadTokenItems() {
        if AppSettings.multiVaultBalancesEnabled {
            #if DEBUG
            LogService.shared.debug("[Multivault] Loading balances for all safes")
            #endif
            loadMultiVaultBalances()
        } else {
            #if DEBUG
            LogService.shared.debug("[Multivault] Flag off, loading selected safe only")
            #endif
            loadSingleVaultBalances()
        }
    }

    override func reloadData() {
        super.reloadData()
        cancelRunningTasks()
        
        #if DEBUG
        LogService.shared.debug("[Multivault] reloadData start. flag=\(AppSettings.multiVaultBalancesEnabled)")
        #endif
        
        if let safe = try? Safe.getSelected(), safe.chain?.isSupported(feature: .moonpay) ?? false {
            emptyView.setTitle(NSLocalizedString("ui_balances_empty_title", comment: "Balances empty title"))
            emptyView.setDescription(NSLocalizedString("ui_balances_empty_description", comment: "Balances empty description"))
            emptyView.setAction(text: NSLocalizedString("ui_buy_crypto_title", comment: "Buy crypto title"), action: { [weak self] in
                guard let safe = try? Safe.getSelected() else {
                    return
                }

                Tracker.trackEvent(.userBuyCrypto)
                let vc = ViewControllerFactory.selectTopUpAddress(safe: safe)

                self?.present(vc, animated: true)
            })
        } else {
            emptyView.setTitle(NSLocalizedString("ui_balances_empty_alt_title", comment: "Balances empty alternate title"))
            emptyView.setDescription(nil)
            emptyView.setAction(text: nil) { }
        }
        
        loadTokenItems()
    }

    /// Applies token items to the UI, including sectioning and notifications used by container screens.
    /// Subclasses with custom loaders should call this when data is ready.
    func apply(items: [TokenBalance],
               totalFiat: String? = nil,
               transferSelectableAssets: [TransferSelectableAsset]? = nil) {
        // Backwards compatible entry point: treat the same list as both raw + display.
        apply(rawItems: items,
              displayItems: items,
              totalFiat: totalFiat,
              transferSelectableAssets: transferSelectableAssets)
    }

    /// Applies raw (contract-level) and display (possibly grouped) items.
    /// - Important: `rawItems` is published via `.balanceUpdated` and is consumed by the send/withdraw flows.
    ///   Keep it ungrouped to avoid ambiguity when multiple contracts share a single label.
    func apply(rawItems: [TokenBalance],
               displayItems: [TokenBalance]? = nil,
               totalFiat: String? = nil,
               transferSelectableAssets: [TransferSelectableAsset]? = nil,
               postBalanceUpdated: Bool = true) {
        if postBalanceUpdated {
            NotificationCenter.default.post(
                name: .balanceUpdated,
                object: self,
                userInfo: {
                    var info: [AnyHashable: Any] = [
                        "balances": rawItems,
                        "total": totalFiat ?? TokenBalance.displayCurrency(from: "0", code: AppSettings.selectedFiatCode)
                    ]
                    if let transferSelectableAssets {
                        info["transferSelectableAssets"] = transferSelectableAssets
                    }
                    return info
                }()
            )
        }
        let display = displayItems ?? rawItems
        sections = makeSections(items: display)

        #if DEBUG
        do {
            let total = display.count
            let categoryCounts = Dictionary(grouping: display, by: { $0.category.lowercased() }).mapValues(\.count)
            let sectionCounts = Dictionary(grouping: display, by: { mapCategoryToSectionId($0) }).mapValues(\.count)
            let mm = display.filter { mapCategoryToSectionId($0) == "moneymarket" }
            let mmSyms = mm.map { "\($0.symbol)(\($0.address.prefix(6))..)" }.joined(separator: ", ")
            LogService.shared.debug(
                """
                [Balances][MoneyMarket][UI] apply displayCount=\(total) \
                sectionCounts=\(sectionCounts) categoryCounts=\(categoryCounts) \
                moneyMarketCount=\(mm.count) moneyMarketItems=[\(mmSyms)]
                """
            )
        }
        #endif

        // Important: reload the table (via `onSuccess`) before triggering any yield callbacks that may
        // reload specific rows. Otherwise, if the section set changes (e.g. adding moneymarket),
        // `reloadRows(at:)` can crash due to a section-count mismatch.
        onSuccess()
        refreshMoneyMarketYieldsIfNeeded(displayItems: display)
        refreshSavingsEthYieldsIfNeeded(displayItems: display)
    }

    // MARK: - Money market yield helpers

    private func refreshMoneyMarketYieldsIfNeeded(displayItems: [TokenBalance]) {
        // Identify money market items by the same normalization used for section mapping.
        let moneyMarketItems = displayItems.filter { mapCategoryToSectionId($0) == "moneymarket" }

        #if DEBUG
        if moneyMarketItems.isEmpty {
            // Useful when Money market disappears: show whether we even have any tokens whose *raw category*
            // is moneymarket but got grouped under a different section.
            let rawMm = displayItems.filter {
                $0.category
                    .lowercased()
                    .replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: "-", with: "")
                    .replacingOccurrences(of: "_", with: "") == "moneymarket"
            }
            if !rawMm.isEmpty {
                let rawMmSyms = rawMm.map { "\($0.symbol)(\($0.address.prefix(6)).. sec=\(mapCategoryToSectionId($0)))" }.joined(separator: ", ")
                LogService.shared.debug("[Balances][MoneyMarket][UI] No moneymarket section items, but found rawCategory=moneymarket items: [\(rawMmSyms)]")
            } else {
                LogService.shared.debug("[Balances][MoneyMarket][UI] No moneymarket items detected in display list.")
            }
        }
        #endif

        guard !moneyMarketItems.isEmpty else {
            // Clear any stale badge values when no longer relevant.
            if !moneyMarketApyByTokenAddress.isEmpty || !moneyMarketApyDisplayBySymbolKey.isEmpty {
                moneyMarketApyByTokenAddress = [:]
                moneyMarketApyDisplayBySymbolKey = [:]
                reloadMoneyMarketRows()
            }
            return
        }

        // Invertir “markets” rows are not chain-specific; use Ethereum Aave supply APY by underlying symbol.
        if useEthereumUnderlyingApyForMoneyMarket {
            refreshMoneyMarketYieldsUsingEthereumUnderlying(moneyMarketItems: moneyMarketItems)
            return
        }

        let fallbackChainId = (try? Safe.getSelected())?.chain?.id
        let fallbackChainIdInt = fallbackChainId.flatMap(Int.init)

        // Build MoneyMarket memberships per displayed symbol from *raw* inputs when available (multi-vault),
        // otherwise fall back to the displayed list.
        var membersBySymbolKey: [String: Set<MoneyMarketYieldService.QueryKey>] = [:]

        if !latestBalanceInputs.isEmpty {
            for (chainIdStr, summary) in latestBalanceInputs {
                guard let chainIdInt = Int(chainIdStr) else { continue }
                for raw in summary.items {
                    let category = (raw.tokenCategory ?? "blackToken")
                        .lowercased()
                        .replacingOccurrences(of: " ", with: "")
                        .replacingOccurrences(of: "-", with: "")
                        .replacingOccurrences(of: "_", with: "")
                    guard category == "moneymarket" else { continue }

                    let addrChecksummed = raw.tokenInfo.address.address.checksummed
                    let addrLower = addrChecksummed.lowercased()
                    let rawSymbol = (raw.tokenSymbol ?? raw.tokenInfo.symbol) ?? ""
                    let tokenSymbol = rawSymbol.trimmingCharacters(in: .whitespacesAndNewlines)
                    let wrap = (raw.wrapLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let displaySymbol = wrap.isEmpty ? tokenSymbol : wrap
                    let symbolKey = displaySymbol.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    guard !symbolKey.isEmpty else { continue }

                    membersBySymbolKey[symbolKey, default: []].insert(.init(chainId: chainIdInt, aTokenAddressLowercased: addrLower))
                }
            }
        }

        // For each money market row in the display list, gather its underlying per-chain aTokens.
        // If we can't find any members for the symbol, fall back to the row's own address + selected chain.
        var allKeys: Set<MoneyMarketYieldService.QueryKey> = []
        allKeys.reserveCapacity(moneyMarketItems.count)
        var symbolMembers: [String: Set<MoneyMarketYieldService.QueryKey>] = [:]
        symbolMembers.reserveCapacity(moneyMarketItems.count)

        for item in moneyMarketItems {
            let symbolKey = item.symbol.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var memberSet = membersBySymbolKey[symbolKey] ?? []
            if memberSet.isEmpty, let chainIdInt = fallbackChainIdInt {
                memberSet.insert(.init(chainId: chainIdInt, aTokenAddressLowercased: item.address.lowercased()))
            }
            guard !memberSet.isEmpty else { continue }
            symbolMembers[symbolKey] = memberSet
            for k in memberSet { allKeys.insert(k) }
        }

        let keys = Array(allKeys)
        guard !keys.isEmpty else {
            #if DEBUG
            let mm = moneyMarketItems.map { "\($0.symbol) addr=\($0.address) cat=\($0.category)" }.joined(separator: " | ")
            LogService.shared.debug("[Balances][MoneyMarket][APY] Skipping fetch: keys empty. fallbackChainId=\(fallbackChainId ?? "nil") mmItems=\(mm)")
            #endif
            return
        }

        #if DEBUG
        let keySummary = Dictionary(grouping: keys, by: { $0.chainId }).mapValues { $0.count }
        LogService.shared.debug("[Balances][MoneyMarket][APY] Will fetch APY for keysCount=\(keys.count) byChain=\(keySummary)")
        #endif

        moneyMarketYieldGeneration += 1
        let generation = moneyMarketYieldGeneration

        moneyMarketYieldService.fetchApyPercents(keys: keys) { [weak self] result in
            guard let self else { return }
            guard generation == self.moneyMarketYieldGeneration else { return }

            switch result {
            case .failure:
                #if DEBUG
                LogService.shared.error("[Balances][MoneyMarket][APY] Fetch failed; clearing badge map")
                #endif
                // Keep UI usable; don't show a stale badge.
                if !self.moneyMarketApyByTokenAddress.isEmpty || !self.moneyMarketApyDisplayBySymbolKey.isEmpty {
                    self.moneyMarketApyByTokenAddress = [:]
                    self.moneyMarketApyDisplayBySymbolKey = [:]
                    self.reloadMoneyMarketRows()
                }
            case .success(let map):
                #if DEBUG
                let missing = keys
                    .map { $0.aTokenAddressLowercased }
                    .filter { map[$0] == nil }
                if !missing.isEmpty {
                    let sample = missing.prefix(12).joined(separator: ",")
                    LogService.shared.debug("[Balances][MoneyMarket][APY] Fetch ok; returned=\(map.count) missingForRequested=\(missing.count) sampleMissing=[\(sample)]")
                } else {
                    LogService.shared.debug("[Balances][MoneyMarket][APY] Fetch ok; returned=\(map.count) (all requested present)")
                }
                #endif
                self.moneyMarketApyByTokenAddress = map

                // Compute per-symbol APY display (single vs range) based on how many networks are contributing.
                var displayBySymbol: [String: MoneyMarketApyDisplay] = [:]
                displayBySymbol.reserveCapacity(symbolMembers.count)
                for (symbolKey, memberKeys) in symbolMembers {
                    let networkCount = Set(memberKeys.map { $0.chainId }).count
                    let yields: [Double] = memberKeys.compactMap { mk in map[mk.aTokenAddressLowercased] }
                    guard let minVal = yields.min(), let maxVal = yields.max() else { continue }
                    displayBySymbol[symbolKey] = MoneyMarketApyDisplay(minPercent: minVal,
                                                                      maxPercent: maxVal,
                                                                      networkCount: networkCount)
                }
                self.moneyMarketApyDisplayBySymbolKey = displayBySymbol
                self.reloadMoneyMarketRows()
            }
        }
    }

    private func reloadMoneyMarketRows() {
        // If the table hasn't been reloaded to match our latest `sections` yet, avoid partial updates.
        if tableView.numberOfSections != sections.count {
            tableView.reloadData()
            return
        }
        let visible = tableView.indexPathsForVisibleRows ?? []
        let mmIndexPaths = visible.filter { indexPath in
            guard indexPath.section < sections.count else { return false }
            guard case .balances(section: let section) = sections[indexPath.section] else { return false }
            return section.id == "moneymarket"
        }
        guard !mmIndexPaths.isEmpty else { return }
        tableView.reloadRows(at: mmIndexPaths, with: .none)
    }

    private func refreshMoneyMarketYieldsUsingEthereumUnderlying(moneyMarketItems: [TokenBalance]) {
        // Map each money market row to an underlying symbol (best-effort heuristic).
        // Examples: AAVEUSDT -> USDT, AUSDT -> USDT, USDY -> USDY.
        var symbolKeyToUnderlyingUpper: [String: String] = [:]
        symbolKeyToUnderlyingUpper.reserveCapacity(moneyMarketItems.count)

        for item in moneyMarketItems {
            let symUpper = item.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !symUpper.isEmpty else { continue }

            let underlyingUpper: String
            if symUpper.hasPrefix("AAVE"), symUpper.count > 4 {
                underlyingUpper = String(symUpper.dropFirst(4))
            } else if symUpper.hasPrefix("A"), symUpper.count > 1,
                      (symUpper.contains("USDT") || symUpper.contains("USDC")) {
                // Covers tokens like AUSDT/AUSDC… while avoiding unrelated symbols like AETH.
                underlyingUpper = String(symUpper.dropFirst(1))
            } else {
                underlyingUpper = symUpper
            }

            let symbolKey = symUpper.lowercased()
            symbolKeyToUnderlyingUpper[symbolKey] = underlyingUpper
        }

        let wantedUnderlyings = Array(Set(symbolKeyToUnderlyingUpper.values)).filter { !$0.isEmpty }
        guard !wantedUnderlyings.isEmpty else { return }

        moneyMarketYieldGeneration += 1
        let generation = moneyMarketYieldGeneration

        #if DEBUG
        LogService.shared.debug("[Balances][MoneyMarket][APY] Using Ethereum-underlying yields for symbols=\(symbolKeyToUnderlyingUpper.count) wantedUnderlyings=\(wantedUnderlyings.sorted())")
        #endif

        savingsYieldService.fetchEthereumSupplyApyPercents(symbolsUpper: wantedUnderlyings) { [weak self] result in
            guard let self else { return }
            guard generation == self.moneyMarketYieldGeneration else { return }

            switch result {
            case .failure(let error):
                #if DEBUG
                LogService.shared.error("[Balances][MoneyMarket][APY] Ethereum-underlying fetch failed; clearing badge map", error: error)
                #endif
                if !self.moneyMarketApyByTokenAddress.isEmpty || !self.moneyMarketApyDisplayBySymbolKey.isEmpty {
                    self.moneyMarketApyByTokenAddress = [:]
                    self.moneyMarketApyDisplayBySymbolKey = [:]
                    self.reloadMoneyMarketRows()
                }
            case .success(let underlyingMap):
                var displayBySymbol: [String: MoneyMarketApyDisplay] = [:]
                displayBySymbol.reserveCapacity(symbolKeyToUnderlyingUpper.count)
                for (symbolKey, underlyingUpper) in symbolKeyToUnderlyingUpper {
                    guard let apy = underlyingMap[underlyingUpper] else { continue }
                    displayBySymbol[symbolKey] = MoneyMarketApyDisplay(minPercent: apy,
                                                                      maxPercent: apy,
                                                                      networkCount: 1)
                }
                #if DEBUG
                LogService.shared.debug("[Balances][MoneyMarket][APY] Ethereum-underlying fetch ok; mappedSymbols=\(displayBySymbol.count) underlyingReturned=\(underlyingMap.count)")
                #endif
                self.moneyMarketApyByTokenAddress = [:]
                self.moneyMarketApyDisplayBySymbolKey = displayBySymbol
                self.reloadMoneyMarketRows()
            }
        }
    }

    private func refreshSavingsEthYieldsIfNeeded(displayItems: [TokenBalance]) {
        let savingsItems = displayItems.filter { mapCategoryToSectionId($0) == "usd" }
        guard !savingsItems.isEmpty else {
            if !savingsEthApyByUnderlyingSymbolUpper.isEmpty {
                savingsEthApyByUnderlyingSymbolUpper = [:]
                reloadSavingsRows()
            }
            return
        }

        let wanted = ["USDC", "USDT"]
        let presentWanted = savingsItems
            .map { $0.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { wanted.contains($0) }
        let uniqueWanted = Array(Set(presentWanted))
        guard !uniqueWanted.isEmpty else {
            if !savingsEthApyByUnderlyingSymbolUpper.isEmpty {
                savingsEthApyByUnderlyingSymbolUpper = [:]
                reloadSavingsRows()
            }
            return
        }

        savingsYieldGeneration += 1
        let generation = savingsYieldGeneration

        #if DEBUG
        LogService.shared.debug("[Balances][Savings][APY] Will fetch Ethereum APY for symbols=\(uniqueWanted)")
        #endif

        savingsYieldService.fetchEthereumSupplyApyPercents(symbolsUpper: uniqueWanted) { [weak self] result in
            guard let self else { return }
            guard generation == self.savingsYieldGeneration else { return }

            switch result {
            case .failure:
                #if DEBUG
                LogService.shared.error("[Balances][Savings][APY] Fetch failed; clearing badge map")
                #endif
                if !self.savingsEthApyByUnderlyingSymbolUpper.isEmpty {
                    self.savingsEthApyByUnderlyingSymbolUpper = [:]
                    self.reloadSavingsRows()
                }
            case .success(let map):
                #if DEBUG
                LogService.shared.debug("[Balances][Savings][APY] Fetch ok; returned=\(map.count) map=\(map)")
                #endif
                self.savingsEthApyByUnderlyingSymbolUpper = map
                self.reloadSavingsRows()
            }
        }
    }

    private func reloadSavingsRows() {
        // If the table hasn't been reloaded to match our latest `sections` yet, avoid partial updates.
        if tableView.numberOfSections != sections.count {
            tableView.reloadData()
            return
        }
        let visible = tableView.indexPathsForVisibleRows ?? []
        let paths = visible.filter { indexPath in
            guard indexPath.section < sections.count else { return false }
            guard case .balances(section: let section) = sections[indexPath.section] else { return false }
            return section.id == "usd"
        }
        guard !paths.isEmpty else { return }
        tableView.reloadRows(at: paths, with: .none)
    }

    private func backfillFiatIfNeeded(
        summary: SafeBalanceSummary,
        chainId: String,
        completion: @escaping (SafeBalanceSummary) -> Void
    ) {
        func finish(_ value: SafeBalanceSummary) {
            DispatchQueue.main.async {
                completion(value)
            }
        }
        let symbols = BalanceFiatBackfill.requiredSymbols(summary: summary, chainId: chainId)
        guard !symbols.isEmpty else {
            finish(summary)
            return
        }

        marketCapPricesService.fetchPrices(symbols: symbols) { result in
            switch result {
            case .success(let prices):
                let backfill = BalanceFiatBackfill.apply(summary: summary, chainId: chainId, pricesBySymbol: prices)
                #if DEBUG
                LogService.shared.debug(
                    "[Balances][FiatBackfill] chainId=\(chainId) symbols=\(symbols.count) updated=\(backfill.updatedCount) missing=\(backfill.missingSymbols.count)"
                )
                #endif
                finish(backfill.summary)
            case .failure(let error):
                #if DEBUG
                LogService.shared.error("[Balances][FiatBackfill] Price fetch failed; using gateway values", error: error)
                #endif
                finish(summary)
            }
        }
    }

    private func backfillFiatIfNeeded(
        inputs: [(chainId: String, summary: SafeBalanceSummary)],
        completion: @escaping ([(chainId: String, summary: SafeBalanceSummary)]) -> Void
    ) {
        func finish(_ value: [(chainId: String, summary: SafeBalanceSummary)]) {
            DispatchQueue.main.async {
                completion(value)
            }
        }
        let symbols = BalanceFiatBackfill.requiredSymbols(inputs: inputs)
        guard !symbols.isEmpty else {
            finish(inputs)
            return
        }

        marketCapPricesService.fetchPrices(symbols: symbols) { result in
            switch result {
            case .success(let prices):
                let updated = inputs.map { input -> (chainId: String, summary: SafeBalanceSummary) in
                    let backfill = BalanceFiatBackfill.apply(
                        summary: input.summary,
                        chainId: input.chainId,
                        pricesBySymbol: prices
                    )
                    return (chainId: input.chainId, summary: backfill.summary)
                }
                #if DEBUG
                LogService.shared.debug("[Balances][FiatBackfill] multiVault symbols=\(symbols.count) prices=\(prices.count)")
                #endif
                finish(updated)
            case .failure(let error):
                #if DEBUG
                LogService.shared.error("[Balances][FiatBackfill] multiVault price fetch failed", error: error)
                #endif
                finish(inputs)
            }
        }
    }

    private func loadSingleVaultBalances() {
        guard let safe = try? Safe.getSelected(), let chainId = safe.chain?.id else {
            return
        }
        #if DEBUG
        LogService.shared.debug("[Multivault] Single-vault path for \(safe.address ?? "nil") on chain \(chainId)")
        #endif
        NotificationCenter.default.post(
            name: .balanceLoading,
            object: self
        )
        // Include untrusted/custom tokens while excluding spam (matches Invest buy-flow "pay with" screen).
        let query = "trusted=false&exclude_spam=true"
        currentDataTask = clientGatewayService.asyncBalances(safeAddress: safe.addressValue,
                                                             chainId: chainId,
                                                             query: query) { [weak self] result in
            guard let `self` = self else { return }
            switch result {
            case .failure(let error):
                DispatchQueue.main.async { [weak self] in
                    guard let `self` = self else { return }
                    if self.isCancellation(error: error) { return }
                    #if DEBUG
                    LogService.shared.error("[Multivault] Single-vault fetch failed", error: error)
                    #endif
                    self.onError(GSError.error(description: NSLocalizedString("ui_balances_failed_load_error", comment: "Failed to load balances error"),
                                               error: error))
                }
            case .success(let summary):
                DispatchQueue.main.async { [weak self] in
                    guard let `self` = self else { return }
                    self.backfillFiatIfNeeded(summary: summary, chainId: chainId) { updatedSummary in
                        self.latestBalanceInputs = [(chainId: chainId, summary: updatedSummary)]
                        let results = updatedSummary.items.map {
                            TokenBalance($0, code: AppSettings.selectedFiatCode, chainId: chainId)
                        }
                        let total = TokenBalance.displayCurrency(
                            from: updatedSummary.fiatTotal,
                            code: AppSettings.selectedFiatCode
                        )
                        #if DEBUG
                        LogService.shared.debug("[Multivault] Single-vault fetched \(results.count) token(s); total=\(total)")
                        if let doc = results.first(where: { $0.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "DOC" }) {
                            LogService.shared.debug("[Balances][DOC] found addr=\(doc.address) cat=\(doc.category) amt=\(doc.balanceFormatted5) fiat=\(doc.fiatBalance)")
                        }
                        #endif
                        let displayItems: [TokenBalance]
                        if let displaySummary = updatedSummary.display {
                            displayItems = displaySummary.items.map {
                                TokenBalance($0, code: AppSettings.selectedFiatCode, chainId: chainId)
                            }
                        } else {
                            displayItems = results
                        }
                        self.apply(rawItems: results, displayItems: displayItems, totalFiat: total)
                    }
                }
            }
        }
    }
    
    private func loadMultiVaultBalances() {
        let fiatCode = AppSettings.selectedFiatCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard fiatCode == "USD" else {
            #if DEBUG
            LogService.shared.debug("[Multivault] Non-USD fiat=\(fiatCode) detected; falling back to legacy multi-vault fetch")
            #endif
            loadMultiVaultBalancesLegacy()
            return
        }

        guard let safes = try? Safe.getAll() else { return }
        let deployedSafes = safes.filter { $0.safeStatus == .deployed }
        if deployedSafes.isEmpty {
            #if DEBUG
            LogService.shared.debug("[Multivault] No deployed safes found for aggregation")
            #endif
            return
        }

        #if DEBUG
        LogService.shared.debug("[Multivault] Using backend multivault endpoint for \(deployedSafes.count) safe(s)")
        #endif

        NotificationCenter.default.post(
            name: .balanceLoading,
            object: self
        )

        let safeEntries = deployedSafes.compactMap { safe -> MultiVaultBalancesRequest.SafeEntry? in
            guard let chainId = safe.chain?.id, let address = safe.address else { return nil }
            return .init(chainId: chainId, safe: address)
        }

        let addressToObjectId: [String: NSManagedObjectID] = deployedSafes.reduce(into: [:]) { acc, safe in
            if let address = safe.address?.lowercased() {
                acc[address] = safe.objectID
            }
        }

        let userId = App.shared.authRepository.getCurrentUser()?.uid
        let request = MultiVaultBalancesRequest(
            fiat: "USD",
            userId: userId,
            safes: userId == nil ? safeEntries : nil,
            maxConcurrent: 3
        )
        currentDataTask = App.shared.clientGatewayService.asyncExecute(request: request) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .failure(let error):
                    if self.isCancellation(error: error) { return }
                    #if DEBUG
                    LogService.shared.error("[Multivault] Backend multivault fetch failed", error: error)
                    #endif
                    self.onError(GSError.error(description: NSLocalizedString("ui_balances_failed_load_error", comment: "Failed to load balances error"),
                                               error: error))
                case .success(let response):
                    let perSafe = response.perSafe
                    if perSafe.isEmpty {
                        #if DEBUG
                        LogService.shared.error("[Multivault] Backend multivault returned empty results")
                        #endif
                        self.onError(GSError.error(description: NSLocalizedString("ui_balances_failed_load_error", comment: "Failed to load balances error")))
                        return
                    }

                    let updatedInputs = perSafe.map { (chainId: $0.chainId, summary: $0.summary) }
                    self.latestBalanceInputs = updatedInputs

                    let updatedResults: [(safeObjectID: NSManagedObjectID, chainId: String, summary: SafeBalanceSummary)] =
                        perSafe.compactMap { entry in
                            guard let safeObjectID = addressToObjectId[entry.safe.lowercased()] else { return nil }
                            return (safeObjectID: safeObjectID, chainId: entry.chainId, summary: entry.summary)
                        }

                    var transferSelectableAssets: [TransferSelectableAsset]?
                    if AppSettings.multiVaultBalancesEnabled {
                        transferSelectableAssets = MultiVaultTransferAssetsAggregator.aggregate(
                            updatedResults,
                            fiatCode: AppSettings.selectedFiatCode
                        )
                    }
                    let displaySummary = response.display ?? response.aggregated.map {
                        SafeBalanceDisplay(fiatTotal: $0.fiatTotal, items: $0.items)
                    }
                    if let displaySummary {
                        let displayItems = displaySummary.items.map {
                            TokenBalance($0, code: AppSettings.selectedFiatCode, chainId: "")
                        }
                        let totalFiat = TokenBalance.displayCurrency(from: displaySummary.fiatTotal,
                                                                    code: AppSettings.selectedFiatCode)
                        let rawItems = updatedInputs.flatMap { input in
                            input.summary.items.map { TokenBalance($0, code: AppSettings.selectedFiatCode, chainId: input.chainId) }
                        }
                        #if DEBUG
                        let symbols = displayItems.map { "\($0.symbol)=\($0.balance)" }.joined(separator: ", ")
                        LogService.shared.debug("[Multivault] Display list \(displayItems.count) token(s). Symbols: [\(symbols)] totalFiat=\(totalFiat)")
                        #endif
                        self.apply(rawItems: rawItems,
                                   displayItems: displayItems,
                                   totalFiat: totalFiat,
                                   transferSelectableAssets: transferSelectableAssets)
                    } else {
                        let aggregated = MultiVaultBalancesAggregator.aggregate(
                            updatedInputs,
                            fiatCode: AppSettings.selectedFiatCode
                        )
                        #if DEBUG
                        let symbols = aggregated.balances.map { "\($0.symbol)=\($0.balance)" }.joined(separator: ", ")
                        LogService.shared.debug("[Multivault] Aggregated \(aggregated.balances.count) token(s) across \(updatedInputs.count) safe(s). Symbols: [\(symbols)] totalFiat=\(aggregated.totalFiat)")
                        #endif
                        self.apply(rawItems: aggregated.rawBalances,
                                   displayItems: aggregated.balances,
                                   totalFiat: aggregated.totalFiat,
                                   transferSelectableAssets: transferSelectableAssets)
                    }
                }
            }
        }
    }

    private func loadMultiVaultBalancesLegacy() {
        guard let safes = try? Safe.getAll() else { return }
        let deployedSafes = safes.filter { $0.safeStatus == .deployed }
        if deployedSafes.isEmpty {
            #if DEBUG
            LogService.shared.debug("[Multivault] No deployed safes found for aggregation")
            #endif
            return
        }
        
        #if DEBUG
        LogService.shared.debug("[Multivault] Will aggregate \(deployedSafes.count) deployed safe(s)")
        #endif
        
        NotificationCenter.default.post(
            name: .balanceLoading,
            object: self
        )
        
        let group = DispatchGroup()
        let syncQueue = DispatchQueue(label: "io.gnosis.multisig.multivault", qos: .userInitiated)
        let requestQueue = DispatchQueue(label: "io.gnosis.multisig.multivault.requests", qos: .userInitiated, attributes: .concurrent)
        let maxConcurrentRequests = 3
        let semaphore = DispatchSemaphore(value: maxConcurrentRequests)
        let maxAttempts = 4

        var results: [(safeObjectID: NSManagedObjectID, chainId: String, summary: SafeBalanceSummary)] = []
        var firstError: Error?

        func isRetryableRateLimit(error: Error) -> Bool {
            (error as? DetailedLocalizedError)?.code == 429
        }

        func isRetryableServerError(error: Error) -> Bool {
            guard let e = error as? DetailedLocalizedError else { return false }
            return [500, 502, 503, 504].contains(e.code)
        }

        func backoffDelaySeconds(attempt: Int) -> TimeInterval {
            // attempt: 1 (no delay), 2 (1s), 3 (2s), 4 (4s) ...
            if attempt <= 1 { return 0 }
            return min(30, pow(2, Double(attempt - 2)))
        }

        for safe in deployedSafes {
            guard let chain = safe.chain, let chainId = chain.id else {
                #if DEBUG
                LogService.shared.debug("[Multivault] Skipping safe without chain id: \(safe.address ?? "nil")")
                #endif
                continue
            }

            group.enter()

            requestQueue.async { [weak self] in
                guard let self else { group.leave(); return }
                semaphore.wait()

                #if DEBUG
                LogService.shared.debug("[Multivault] Starting balance fetch (throttled) safe=\(safe.address ?? "unknown") chain=\(chainId) maxConcurrent=\(maxConcurrentRequests)")
                #endif

                let service = chain.gatewayService()

                func attemptFetch(_ attempt: Int) {
                    let delay = backoffDelaySeconds(attempt: attempt)
                    if delay > 0 {
                        #if DEBUG
                        LogService.shared.debug("[Multivault] Retry scheduled in \(Int(delay * 1000))ms attempt=\(attempt)/\(maxAttempts) safe=\(safe.address ?? "unknown") chain=\(chainId)")
                        #endif
                    }

                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) { [weak self] in
                        guard let self else {
                            semaphore.signal()
                            syncQueue.async { group.leave() }
                            return
                        }

                        let start = Date()
                        let task = service.asyncBalances(safeAddress: safe.addressValue,
                                                         chainId: chainId) { [weak self] result in
                            guard self != nil else { return }
                            let duration = Date().timeIntervalSince(start)

                            switch result {
                            case .success(let summary):
                                #if DEBUG
                                LogService.shared.debug("[Multivault] Loaded balances attempt=\(attempt) safe=\(safe.address ?? "unknown") chain=\(chainId) in \(Int(duration * 1000))ms (\(summary.items.count) items)")
                                #endif
                                syncQueue.async {
                                    results.append((safeObjectID: safe.objectID, chainId: chainId, summary: summary))
                                    semaphore.signal()
                                    group.leave()
                                }
                            case .failure(let error):
                                let shouldRetry = attempt < maxAttempts && (isRetryableRateLimit(error: error) || isRetryableServerError(error: error))
                                #if DEBUG
                                let code = (error as? DetailedLocalizedError)?.code
                                LogService.shared.error("[Multivault] Failed balances attempt=\(attempt) safe=\(safe.address ?? "unknown") chain=\(chainId) in \(Int(duration * 1000))ms code=\(code.map(String.init) ?? "nil") retry=\(shouldRetry)", error: error)
                                #endif

                                if shouldRetry {
                                    attemptFetch(attempt + 1)
                                    return
                                }

                                syncQueue.async {
                                    if firstError == nil { firstError = error }
                                    semaphore.signal()
                                    group.leave()
                                }
                            }
                        }

                        if let task = task {
                            DispatchQueue.main.async { [weak self] in
                                self?.currentDataTasks.append(task)
                            }
                        } else {
                            syncQueue.async {
                                if firstError == nil {
                                    firstError = GSError.error(description: NSLocalizedString("ui_balances_failed_start_request_error", comment: "Failed to start balances request error"))
                                }
                                semaphore.signal()
                                group.leave()
                            }
                        }
                    }
                }

                attemptFetch(1)
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.currentDataTasks.removeAll()
            if results.isEmpty {
                // Treat pure cancellations as a non-fatal/no-op to avoid spurious error toasts
                if let error = firstError, !self.isCancellation(error: error) {
                    #if DEBUG
                    LogService.shared.error("[Multivault] All requests failed; showing error", error: error)
                    #endif
                    self.onError(GSError.error(description: NSLocalizedString("ui_balances_failed_load_error", comment: "Failed to load balances error"),
                                               error: error))
                } else {
                    #if DEBUG
                    LogService.shared.error("[Multivault] Requests cancelled; suppressing error toast")
                    #endif
                }
                return
            }

            let rawInputs = results.map { (chainId: $0.chainId, summary: $0.summary) }
            self.backfillFiatIfNeeded(inputs: rawInputs) { updatedInputs in
                let updatedResults: [(safeObjectID: NSManagedObjectID, chainId: String, summary: SafeBalanceSummary)] =
                    zip(results, updatedInputs).map { original, updated in
                        (safeObjectID: original.safeObjectID, chainId: original.chainId, summary: updated.summary)
                    }
                let aggregated = MultiVaultBalancesAggregator.aggregate(
                    updatedInputs,
                    fiatCode: AppSettings.selectedFiatCode
                )
                self.latestBalanceInputs = updatedInputs
                var transferSelectableAssets: [TransferSelectableAsset]?
                if AppSettings.multiVaultBalancesEnabled {
                    transferSelectableAssets = MultiVaultTransferAssetsAggregator.aggregate(updatedResults,
                                                                                            fiatCode: AppSettings.selectedFiatCode)
                }
                #if DEBUG
                let symbols = aggregated.balances.map { "\($0.symbol)=\($0.balance)" }.joined(separator: ", ")
                LogService.shared.debug("[Multivault] Aggregated \(aggregated.balances.count) token(s) across \(results.count) safe(s). Symbols: [\(symbols)] totalFiat=\(aggregated.totalFiat)")
                #endif
                self.apply(rawItems: aggregated.rawBalances,
                           displayItems: aggregated.balances,
                           totalFiat: aggregated.totalFiat,
                           transferSelectableAssets: transferSelectableAssets)
            }
        }
    }
    
    private func cancelRunningTasks() {
        currentDataTask?.cancel()
        currentDataTasks.forEach { $0.cancel() }
        currentDataTasks.removeAll()
    }
    
    private func isCancellation(error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.code == URLError.cancelled.rawValue && nsError.domain == NSURLErrorDomain
    }
    
    private func makeSections(items: [TokenBalance]) -> [Section] {
        guard !isEmptyAccount(items: items) else { return [] }

        var sections = [Section]()

        if shouldShowImportKeyBanner {
            sections.append(.importKeyBanner)
        } else if shouldShowPasscodeBanner {
            sections.append(.passcodeBanner)
        }

        let balanceSections = makeBalanceSections(items: items)
        sections.append(contentsOf: balanceSections.map { .balances(section: $0) })
        return sections
    }
    
    private func isEmptyAccount(items: [TokenBalance]) -> Bool {
        // "Empty account" heuristic:
        // The gateway typically includes the native token row even if the balance is 0.
        // Historically we treated a single zero-balance item as empty, but that breaks
        // "markets" lists (Invertir) where all rows are intentionally zero-balance.
        //
        // So: only treat the account as empty when the *only* item is the native token and it's 0.
        guard let only = items.first else { return true }
        guard items.count == 1 else { return false }

        let isNative = only.address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == TokenBalance.nativeTokenAddress.lowercased()
        let isZero = only.balanceValue.value == 0
        return isNative && isZero
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sections[section] {
        case .importKeyBanner, .passcodeBanner: return 1
        case .balances(section: let section): return section.items.count
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard indexPath.section < sections.count else { return UITableViewCell() }
        switch sections[indexPath.section] {
        case .importKeyBanner:
            return importKeyBanner(indexPath: indexPath)
        case .passcodeBanner:
            return createPasscodeBanner(indexPath: indexPath)
        case .balances(section: let section):
            guard indexPath.row < section.items.count else { return UITableViewCell() }
            let item = section.items[indexPath.row]
            let cell = tableView.dequeueCell(BalanceTableViewCell.self, for: indexPath)
            cell.setMainText(item.symbol)
            if hideFiatAndAmount {
                cell.setDetailText("")
                cell.setSubDetailText("")
            } else {
                cell.setDetailText(item.fiatBalance)           // highlight fiat value (2 decimals from formatter)
                cell.setSubDetailText(item.balanceFormatted5)  // secondary: token amount (up to 5 decimals)
            }
            configureBadge(for: cell, item: item, section: section)
            // Token rows drill into TokenDetail, so keep them selectable and show a chevron.
            cell.selectionStyle = .default
            cell.accessoryType = .none
            cell.setDisclosureVisible(true)
            if let image = item.image {
                cell.setImage(image)
            } else {
                cell.setImage(with: item.imageURL, placeholder: UIImage(named: "ico-token-placeholder")!)
            }
            return cell
        }
    }

    /// Configures the badge for a balance cell. Override in subclasses to customize badge behavior.
    /// Assets tab: no badges (returns nil)
    /// Invertir tab: shows badges based on section/category
    func configureBadge(for cell: BalanceTableViewCell, item: TokenBalance, section: BalanceCategorySection) {
        if section.id == "moneymarket" {
            let symbolKey = item.symbol.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let display = moneyMarketApyDisplayBySymbolKey[symbolKey] {
                let text: String
                // If the token exists on multiple networks, show a range "low%~high%".
                if display.networkCount > 1, abs(display.maxPercent - display.minPercent) > 0.000_001 {
                    let low = formatApyBadgeText(apyPercent: display.minPercent)
                    let high = formatApyBadgeText(apyPercent: display.maxPercent)
                    text = "\(low)~\(high)"
                } else {
                    text = formatApyBadgeText(apyPercent: display.maxPercent)
                }
                cell.setBadge(text: text, backgroundColor: .success)
            } else if let apy = moneyMarketApyByTokenAddress[item.address.lowercased()] {
                // Fallback if we only have per-address APY.
                cell.setBadge(text: formatApyBadgeText(apyPercent: apy), backgroundColor: .success)
            } else {
                cell.setBadge(text: nil)
            }
        } else if section.id == "usd" {
            let sym = item.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if ["USDC", "USDT"].contains(sym), let apy = savingsEthApyByUnderlyingSymbolUpper[sym] {
                // Make the USD yield badge more visible while keeping text readable in both themes:
                // - Use a light "primary" pill background in all modes
                // - Use dark text in dark mode (since the pill is light), otherwise labelPrimary
                let usdYieldTextColor = UIColor { trait in
                    trait.userInterfaceStyle == .dark ? UIColor.backgroundPrimary : UIColor.labelPrimary
                }
                cell.setBadge(text: formatApyBadgeText(apyPercent: apy),
                              backgroundColor: .primary,
                              textColor: usdYieldTextColor)
            } else {
                cell.setBadge(text: nil)
            }
        } else {
            // Assets tab: no badges
            cell.setBadge(text: nil)
        }
    }

    private func formatApyBadgeText(apyPercent: Double) -> String {
        guard apyPercent > 0 else { return "0.00%" }
        if apyPercent > 0, apyPercent < 0.01 {
            return "<0.01%"
        }
        return String(format: "%.2f%%", apyPercent)
    }
    
    private func showSend(balance: TokenBalance) {
        Tracker.trackEvent(.assetsTransferSelectedAsset)
        let transferFundsVC = TransferAmountViewController()
        transferFundsVC.tokenBalance = balance
        let ribbon = ViewControllerFactory.ribbonWith(viewController: transferFundsVC)
        present(ViewControllerFactory.modal(viewController: ribbon), animated: true)
    }

    private func importKeyBanner(indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueCell(BannerTableViewCell.self, for: indexPath)
        cell.setHeader(ImportKeyBanner.Strings.header)
        cell.setBody(ImportKeyBanner.Strings.body)
        cell.setButton(ImportKeyBanner.Strings.button)
        cell.onClose = { [unowned self] in
            importKeyBannerWasShown = true

            recreateSectionsWithCurrentItems()

            Tracker.trackEvent(.bannerImportOwnerKeySkipped)
        }
        cell.onImport = { [unowned self] in
            importKeyBannerWasShown = true

            recreateSectionsWithCurrentItems()

            let vc = ViewControllerFactory.addOwnerViewController {
                self.dismiss(animated: true, completion: nil)
            }
            present(vc, animated: true)
            Tracker.trackEvent(.bannerImportOwnerKeyAdd)
        }
        cell.selectionStyle = .none
        return cell
    }

    private func createPasscodeBanner(indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueCell(BannerTableViewCell.self, for: indexPath)
        cell.setHeader(PasscodeBanner.Strings.header)
        cell.setBody(PasscodeBanner.Strings.body)
        cell.setButton(PasscodeBanner.Strings.button)
        cell.onClose = { [unowned self] in
            AppSettings.passcodeBannerDismissed = true
            recreateSectionsWithCurrentItems()
            Tracker.trackEvent(.skipPasscodeBanner)
        }
        cell.onImport = { [unowned self] in
            AppSettings.passcodeBannerDismissed = true
            recreateSectionsWithCurrentItems()

            createPasscodeFlow = CreatePasscodeFlow(completion: { [unowned self] _ in
                createPasscodeFlow = nil
                recreateSectionsWithCurrentItems()
            })
            present(flow: createPasscodeFlow)

            Tracker.trackEvent(.setupPasscodeFromBanner)
        }
        cell.selectionStyle = .none
        return cell
    }

    private func recreateSectionsWithCurrentItems() {
        let items = allBalances(in: sections)
        sections = makeSections(items: items)
        tableView.reloadData()
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard case .balances(section: let balanceSection) = sections[section] else {
            return nil
        }
        // Do not render a header for the usd section.
        if balanceSection.id == "usd" {
            return nil
        }
        let view = tableView.dequeueHeaderFooterView(BasicHeaderView.self)
        view.setName(balanceSection.title)
        return view
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard case .balances(section: let balanceSection) = sections[section] else { return 0 }
        if balanceSection.id == "usd" {
            return 0
        }
        return BasicHeaderView.headerHeight
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section < sections.count else { return }
        guard case .balances(section: let section) = sections[indexPath.section] else { return }
        guard indexPath.row < section.items.count else { return }

        let item = section.items[indexPath.row]
        guard let vc = TokenDetailFactory.makeViewController(token: item, balancesProvider: self) else {
            return
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    /// Section order for balances lists. Subclasses may override to customize ordering.
    var balanceSectionOrder: [(id: String, title: String)] {
        var order: [(id: String, title: String)] = [
            // Keep usd first; its header stays hidden (see `viewForHeaderInSection`).
            (id: TokenCategory.sectionUSD, title: ""),
            (id: TokenCategory.sectionMoneyMarket, title: "Money market"),
            (id: TokenCategory.sectionAcciones, title: "Acciones"),
            (id: TokenCategory.sectionEtfIndices, title: "ETF de indices"),
            (id: TokenCategory.sectionEtfOtros, title: "ETF otros"),
            (id: TokenCategory.sectionOro, title: "Oro"),
            (id: TokenCategory.sectionCripto, title: "Cripto"),
            (id: TokenCategory.sectionRootstock, title: "Rootstock"),
            (id: TokenCategory.sectionOtros, title: "Otros")
        ]

        if App.configuration.services.environment.isDevelopment {
            // Only show blackToken in development builds (Debug + Release).
            order.append((id: TokenCategory.sectionBlackToken, title: "blackToken"))
        }

        return order
    }

    /// Builds sections from token items. Subclasses may override `mapCategoryToSectionId` and `balanceSectionOrder`.
    func makeBalanceSections(items: [TokenBalance]) -> [BalanceCategorySection] {
        var grouped: [String: [TokenBalance]] = [:]
        for item in items {
            let sectionId = mapCategoryToSectionId(item)
            grouped[sectionId, default: []].append(item)
        }

        return balanceSectionOrder.compactMap { entry in
            guard let balances = grouped[entry.id], !balances.isEmpty else { return nil }
            let sortedBalances = balances.sorted { lhs, rhs in
                if lhs.fiatValue == rhs.fiatValue {
                    return lhs.symbol.localizedCaseInsensitiveCompare(rhs.symbol) == .orderedAscending
                }
                return lhs.fiatValue > rhs.fiatValue
            }
            return BalanceCategorySection(id: entry.id, title: entry.title, items: sortedBalances)
        }
    }

    /// Maps token categories to section IDs. Subclasses may override to customize mapping.
    func mapCategoryToSectionId(_ item: TokenBalance) -> String {
        TokenCategory.sectionId(for: item.category)
    }

    private func allBalances(in sections: [Section]) -> [TokenBalance] {
        sections.compactMap { section -> [TokenBalance]? in
            if case .balances(section: let balanceSection) = section {
                return balanceSection.items
            }
            return nil
        }
        .flatMap { $0 }
    }
}

// MARK: - TokenDetailBalancesProvider (stub; populated in per-network-data todo)

extension BalancesViewController: TokenDetailBalancesProvider {
    func savingsBreakdownRows(for token: TokenBalance) -> [NetworkTokenBalanceRow] {
        TokenBalanceBreakdownBuilder.savingsRows(
            inputs: latestBalanceInputs,
            tokenSymbol: token.symbol,
            fiatCode: AppSettings.selectedFiatCode
        )
    }

    func krakenPair(for token: TokenBalance) -> String? {
        let source = (token.priceSource ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard source == "kraken" else { return nil }
        let param = (token.priceSourceParam ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return param.isEmpty ? nil : param
    }

    func moneyMarketHoldings(for token: TokenBalance) -> [(chainId: Int, aTokenAddress: String)] {
        guard TokenCategory.isMoneyMarket(token.category) else { return [] }

        let tappedDisplaySymbolUpper = token.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !tappedDisplaySymbolUpper.isEmpty else { return [] }

        var out: [(chainId: Int, aTokenAddress: String)] = []
        var seen = Set<String>()

        for (chainIdStr, summary) in latestBalanceInputs {
            guard let chainIdInt = Int(chainIdStr) else { continue }
            for raw in summary.items {
                let category = (raw.tokenCategory ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                guard TokenCategory.isMoneyMarket(category) else { continue }

                let wrap = (raw.wrapLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let rawSymbol = (raw.tokenSymbol ?? raw.tokenInfo.symbol ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let displaySymbolUpper = (wrap.isEmpty ? rawSymbol : wrap).uppercased()
                guard displaySymbolUpper == tappedDisplaySymbolUpper else { continue }

                let aToken = raw.tokenInfo.address.address
                guard raw.balance.value > 0 else { continue }

                let key = "\(chainIdInt):\(aToken.checksummed.lowercased())"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                out.append((chainId: chainIdInt, aTokenAddress: aToken.checksummed))
            }
        }

        return out
    }

    func tokenMetadata(chainId: Int, tokenAddress: String) -> TokenBalanceMetadata? {
        let chainIdStr = String(chainId)
        let addrLower = tokenAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !addrLower.isEmpty else { return nil }

        for (cid, summary) in latestBalanceInputs {
            guard cid.trimmingCharacters(in: .whitespacesAndNewlines) == chainIdStr else { continue }
            if let item = summary.items.first(where: { bal in
                bal.tokenInfo.address.address.checksummed.lowercased() == addrLower
            }) {
                return TokenBalanceMetadata(
                    yieldSource: item.yieldSource,
                    priceSource: item.priceSource,
                    aaveMarketPoolAddress: item.aaveMarketPoolAddress,
                    aaveUnderlyingTokenAddress: item.aaveUnderlyingTokenAddress
                )
            }
        }
        return nil
    }
}

extension BalancesViewController {
    enum ImportKeyBanner {
        enum Strings {
            static let header = "Add owner key"
            static let body = "Did you know that you can import your owner key to sign and execute transactions on the go?"
            static let button = "Add owner key now"
        }
    }

    enum PasscodeBanner {
        enum Strings {
            static var header: String {
                NSLocalizedString("ui_passcode_banner_header", comment: "Create passcode banner header")
            }
            static var body: String {
                NSLocalizedString("ui_passcode_banner_body", comment: "Create passcode banner body")
            }
            static var button: String {
                NSLocalizedString("ui_passcode_banner_button", comment: "Create passcode banner button")
            }
        }
    }
}

// MARK: - Multivault Aggregation Helper

struct AggregatedBalances {
    /// Contract-level (ungrouped) balances, used by send/withdraw flows.
    let rawBalances: [TokenBalance]
    /// Display balances (may be grouped by wrapLabel).
    let balances: [TokenBalance]
    let totalFiat: String
}

/// Aggregates balances from multiple safes by token symbol.
/// - Note: Category/logo/decimals come from the first token encountered for a symbol.
enum MultiVaultBalancesAggregator {
    static func aggregate(
        _ inputs: [(chainId: String, summary: SafeBalanceSummary)],
        fiatCode: String
    ) -> AggregatedBalances {
        struct SymbolAggregate {
            var seed: TokenBalance
            var rawBalance: UInt256
            var fiatTotal: Double
            var decimals: Int
            var displaySymbol: String
        }

        #if DEBUG
        struct DebugMember {
            let chainId: String
            let address: String
            let symbol: String
            let category: String
            let fiatValue: Double
            let wrapLabel: String
        }
        var debugMembersByKey: [String: [DebugMember]] = [:]
        #endif
        
        var rawBalances: [TokenBalance] = []
        var aggregates: [String: SymbolAggregate] = [:]
        var totalFiat: Double = 0
        
        for input in inputs {
            let chainId = input.chainId
            for item in input.summary.items {
                let token = TokenBalance(item, code: fiatCode, chainId: chainId)
                rawBalances.append(token)

                let wrap = (item.wrapLabel ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let displaySymbol = wrap.isEmpty ? token.symbol : wrap
                let key = displaySymbol.lowercased()
                let fiatValue = Double(item.fiatBalance) ?? 0
                totalFiat += fiatValue

                #if DEBUG
                debugMembersByKey[key, default: []].append(
                    DebugMember(
                        chainId: chainId,
                        address: token.address,
                        symbol: token.symbol,
                        category: token.category,
                        fiatValue: fiatValue,
                        wrapLabel: wrap
                    )
                )
                #endif
                
                if var entry = aggregates[key] {
                    // Keep max decimals for precise integer summation.
                    let tokenDecimals = max(0, token.decimals)
                    let newDecimals = max(entry.decimals, tokenDecimals)
                    if newDecimals != entry.decimals {
                        entry.rawBalance = entry.rawBalance * pow10(newDecimals - entry.decimals)
                        entry.decimals = newDecimals
                    }
                    let scaled = item.balance.value * pow10(entry.decimals - tokenDecimals)
                    entry.rawBalance = entry.rawBalance + scaled
                    entry.fiatTotal += fiatValue
                    if token.fiatValue > entry.seed.fiatValue {
                        entry.seed = token
                    }
                    aggregates[key] = entry
                } else {
                    aggregates[key] = SymbolAggregate(seed: token,
                                                      rawBalance: item.balance.value,
                                                      fiatTotal: fiatValue,
                                                      decimals: max(0, token.decimals),
                                                      displaySymbol: displaySymbol)
                }
            }
        }

        #if DEBUG
        // Log only the groups relevant to Money market debugging:
        // - groups that used wrapLabel
        // - groups whose members have mixed categories
        // - groups containing any moneymarket member
        for (key, members) in debugMembersByKey {
            let usedWrap = members.contains { !$0.wrapLabel.isEmpty }
            let categories = Set(members.map { $0.category.lowercased() })
            let mixedCats = categories.count > 1
            let hasMoneyMarket = categories.contains("moneymarket")
            guard usedWrap || mixedCats || hasMoneyMarket else { continue }

            let lines = members
                .sorted { $0.fiatValue > $1.fiatValue }
                .prefix(12)
                .map {
                    "chain=\($0.chainId) sym=\($0.symbol) addr=\($0.address.prefix(10)).. cat=\($0.category) fiat=\($0.fiatValue) wrap=\($0.wrapLabel)"
                }
                .joined(separator: " | ")
            LogService.shared.debug("[Multivault][AggDebug] key=\(key) members=\(members.count) usedWrap=\(usedWrap) categories=\(Array(categories)) sample=[\(lines)]")
        }
        #endif
        
        let balances: [TokenBalance] = aggregates.values.map { aggregate in
            let seed = aggregate.seed
            let aggregatedFiat = aggregate.fiatTotal
            let aggregatedBalance = UInt256String(aggregate.rawBalance)
            let decimals = UInt256String(UInt256(aggregate.decimals))
            let address = Address(seed.address) ?? Address.zero
            let logoUri = seed.imageURL?.absoluteString
            let token = TokenBalance(address: address,
                                     name: seed.name,
                                     symbol: aggregate.displaySymbol,
                                     logoUri: logoUri,
                                     tokenBalance: aggregatedBalance,
                                     decimals: decimals,
                                     fiatBalance: String(aggregatedFiat),
                                     fiatConversion: String(seed.fiatConversion),
                                     code: fiatCode,
                                     category: seed.category)
            return token
        }
        
        let totalFiatString = TokenBalance.displayCurrency(from: String(totalFiat), code: fiatCode)
        return AggregatedBalances(rawBalances: rawBalances, balances: balances, totalFiat: totalFiatString)
    }

    private static func pow10(_ exp: Int) -> UInt256 {
        guard exp > 0 else { return 1 }
        var result: UInt256 = 1
        for _ in 0..<exp {
            result = result * 10
        }
        return result
    }
}
