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
            guard let self else { return }
            // IMPORTANT: retain coordinator; otherwise callbacks won't navigate beyond screen 1.
            let flow = InvestBuyFlowCoordinator(presenter: self)
            flow.onDismiss = { [weak self] in
                self?.investBuyFlow = nil
            }
            self.investBuyFlow = flow
            flow.start()
        }

        // Invertir: "- Vender" should start the Invest sell flow (not the generic Retirar/Send flow).
        totalBalanceView.onSendClicked = { [weak self] in
            guard let self else { return }
            guard let safe = try? Safe.getSelected() else { return }

            if safe.isReadOnly {
                let vc = AddOwnerFirstViewController()
                vc.onSuccess = { [weak self] in
                    guard let self else { return }
                    if (try? Safe.getSelected())?.isReadOnly == false {
                        self.startSellFlow()
                    }
                    self.dismiss(animated: true)
                }
                let navigationController = UINavigationController(rootViewController: vc)
                self.present(navigationController, animated: true)
            } else {
                self.startSellFlow()
            }
        }
    }

    private func startSellFlow() {
        // IMPORTANT: retain coordinator; otherwise callbacks won't navigate beyond screen 1.
        let flow = InvestSellFlowCoordinator(presenter: self)
        flow.onDismiss = { [weak self] in
            self?.investSellFlow = nil
        }
        investSellFlow = flow
        flow.start()
    }
}

// MARK: - Invest (Comprar) Flow - Screen 1

/// Screen 1: token selection list for the Invertir "Comprar" flow.
/// Shows the same token list style as the Invertir tab, but excludes Savings (Ahorros) and allows selecting rows.
final class InvestSelectTokenViewController: UIViewController {
    struct BalanceCategorySection {
        let id: String
        let title: String
        let items: [TokenBalance]
    }

    var onTokenSelected: ((TokenBalance) -> Void)?
    var onLoadedBalances: (([TokenBalance]) -> Void)?

    private let tableView = UITableView(frame: .zero, style: .plain)

    private var currentTask: URLSessionTask?
    private var sections: [BalanceCategorySection] = []
    private var isWhitelistSyncInProgress = false

    // Bottom-sticky search UI (same as main Invertir screen)
    private let searchContainerView = UIView()
    private let searchFieldBackgroundView = UIView()
    private let searchTextField = UITextField()
    private var searchBottomConstraint: NSLayoutConstraint?
    private let searchContainerHeight: CGFloat = 64
    private var searchTerm: String = ""

    private var allMarketItems: [TokenBalance] = []

    private var clientGatewayService: BalancesAPI {
        guard let chain = try? Safe.getSelected()?.chain else {
            return App.shared.clientGatewayService
        }
        return chain.gatewayService()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .backgroundPrimary

        navigationItem.title = "¿Qué querés comprar?"
        ViewControllerFactory.addCloseButton(self)

        configureTable()
        configureBottomSearch()

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

    // MARK: - Search (sticky bottom)

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
        sections = makeSections(items: filteredItems(from: allMarketItems, term: searchTerm))
        tableView.reloadData()
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

    private func loadBalances() {
        // Markets: list is derived from whitelist (not user balances).
        guard let safe = try? Safe.getSelected(), let chain = safe.chain else {
            sections = []
            tableView.reloadData()
            return
        }

        let chainId = chain.id ?? ""
        let totalWhitelist = TokenWhitelist.all.count

        #if DEBUG
        do {
            let all = TokenWhitelist.all
            let enabledFalse = all.filter { $0.enabled == false }.count
            let enabledNil = all.filter { $0.enabled == nil }.count
            let missingChainId = all.filter { (($0.chainId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)).isEmpty }.count
            let missingNetwork = all.filter { (($0.network ?? "").trimmingCharacters(in: .whitespacesAndNewlines)).isEmpty }.count
            let uniqueSymbols = Set(all.compactMap { ($0.tokenSymbol ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }.filter { !$0.isEmpty }).count
            LogService.shared.debug("[InvestMarkets] rawWhitelist total=\(all.count) uniqueSymbols=\(uniqueSymbols) enabledFalse=\(enabledFalse) enabledNil=\(enabledNil) missing(chainId=\(missingChainId), network=\(missingNetwork)) chainId=\(chainId) network=\(chain.shortName ?? "nil")")
        }
        #endif

        if totalWhitelist == 0, !isWhitelistSyncInProgress {
            isWhitelistSyncInProgress = true
            #if DEBUG
            LogService.shared.debug("[InvestMarkets] Whitelist empty locally; triggering sync (chainId=\(chainId), network=\(chain.shortName ?? "nil"))")
            #endif
            App.shared.tokenWhitelistRepository.syncWhitelist(force: false, network: nil) { [weak self] result in
                guard let self else { return }
                self.isWhitelistSyncInProgress = false
                switch result {
                case .success:
                    #if DEBUG
                    LogService.shared.debug("[InvestMarkets] Whitelist sync completed; reloading markets")
                    #endif
                    self.loadBalances()
                case .failure(let error):
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

        #if DEBUG
        do {
            let catCounts = Dictionary(grouping: balances) { $0.category.lowercased() }
                .mapValues { $0.count }
                .sorted { $0.value > $1.value }
                .prefix(12)
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ", ")
            let sample = balances.prefix(20).map { "\($0.symbol){cat=\($0.category)}" }.joined(separator: ", ")
            LogService.shared.debug("[InvestMarkets] afterMarkets grouped=\(entries.count) afterSavings=\(balances.count) categories{\(catCounts)} sample[\(min(balances.count, 20))]=[\(sample)] chainId=\(chainId) network=\(chain.shortName ?? "nil")")
        }
        #endif

        self.onLoadedBalances?(balances)
        self.allMarketItems = balances
        self.sections = self.makeSections(items: filteredItems(from: balances, term: searchTerm))

        #if DEBUG
        do {
            let sectionCounts = self.sections.map { "\($0.id)=\($0.items.count)" }.joined(separator: ", ")
            let investSample = self.sections.first(where: { $0.id == "invest" })?.items.prefix(20).map { $0.symbol }.joined(separator: ", ") ?? ""
            LogService.shared.debug("[InvestMarkets] final sections{\(sectionCounts)} investSample[\(min(20, self.sections.first(where: { $0.id == "invest" })?.items.count ?? 0))]=[\(investSample)]")
        }
        #endif

        self.tableView.reloadData()
    }
}

extension InvestSelectTokenViewController {
    private var sectionOrder: [(id: String, title: String)] {
        [
            // Match the main Invertir screen ordering (`InvertirBalancesViewController.balanceSectionOrder`)
            (id: "moneymarket", title: "Money market"),
            (id: "cripto", title: "Cripto"),
            (id: "gold", title: "Oro"),
            (id: "invest", title: "ETF y acciones"),
            (id: "otros", title: "Otros"),
            (id: "blacktoken", title: "blackToken")
        ]
    }

    private func isSavings(_ item: TokenBalance) -> Bool {
        switch item.category.lowercased() {
        case "stablecoin", "stablecoins", "savings":
            return true
        default:
            return false
        }
    }

    /// Allowed categories for the *target* (what the user buys) in v1.
    private func isAllowedTarget(_ item: TokenBalance) -> Bool {
        let normalized = item.category
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
        return ["cripto", "oro", "moneymarket", "invest", "token"].contains(normalized)
    }

    private func mapCategoryToSectionId(_ item: TokenBalance) -> String {
        switch item.category.lowercased() {
        case "moneymarket":
            return "moneymarket"
        case "invest":
            return "invest"
        case "token", "cripto":
            return "cripto"
        case "oro", "gold":
            return "gold"
        case "blacktoken":
            return "blacktoken"
        default:
            return "otros"
        }
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
        let normalizedCategory = item.category
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")

        if section.id == "savings" {
            cell.setBadge(text: "3.75%")
        } else if section.id == "moneymarket" || normalizedCategory == "moneymarket" {
            cell.setBadge(text: "3.75%", backgroundColor: .success)
        } else if ["cripto", "invest", "gold"].contains(section.id) {
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
        } else {
            cell.setBadge(text: nil)
        }
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
        onTokenSelected?(item)
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

    private var debounceTimer: Timer?
    private let debounceDuration: TimeInterval = 0.15

    init(selectedToken: TokenBalance, paymentTotalFiat _: Double, fiatCode: String, paymentBalances: [TokenBalance]) {
        self.selectedToken = selectedToken
        self.fiatCode = fiatCode
        self.paymentBalances = paymentBalances
        self.selectedPaymentToken = paymentBalances.first
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .backgroundPrimary

        title = "¿Con qué querés pagar?"

        configureLayout()
        configureInitialValues()
        recompute()
    }

    func updatePaymentBalances(_ balances: [TokenBalance], totalFiat _: Double) {
        paymentBalances = balances
        // Preserve current selection if possible; otherwise default to first item.
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

        // Re-validate amount if user already typed.
        recompute()
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
        quantityTitleLabel.text = "Vas a comprar"

        quantityValueLabel.setStyle(.title3)
        quantityValueLabel.textColor = .labelPrimary

        continueButton.setText("Continuar", .filled)
        continueButton.isEnabled = false
        continueButton.addTarget(self, action: #selector(didTapContinue), for: .touchUpInside)
        NSLayoutConstraint.activate([
            continueButton.heightAnchor.constraint(equalToConstant: 48)
        ])

        // Payment balances (Savings + Money market)
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
#if DEBUG
        if paymentAssetsTableView.allowsSelection == false || paymentAssetsTableView.delegate == nil {
            LogService.shared.error("[InvestBuy] Payment assets table must be selectable (regression guard)")
        }
#endif

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

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        // Allow all changes; we validate and compute on debounce.
        return true
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

        // Validate against the selected payment token's available fiat value (not the sum of all tokens).
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
        // Unit price derived from (totalFiatValue / totalTokenAmount).
        let totalTokenAmount = decimalValue(from: token.balanceValue)
        guard totalTokenAmount > 0 else { return nil }
        let unit = token.fiatValue / totalTokenAmount
        return unit.isFinite && unit > 0 ? unit : nil
    }

    private func decimalValue(from amount: BigDecimal) -> Double {
        // Convert BigDecimal to Decimal string without grouping, then to Double.
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
        // Fallback: normalize comma to dot.
        let normalized = raw.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private func formatFiat(_ value: Double, code: String) -> String {
        // `displayCurrency` expects an en_US numeric string.
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
        tableView.reloadData() // update checkmarks
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
        title = "Confirmar"
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

        buyButton.setText("Comprar", .filled)
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

/// Stage-1 execution stub screen.
final class InvestPurchaseInProgressViewController: UIViewController {
    var onFinish: (() -> Void)?

    private let titleLabel = UILabel()
    private let button = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .backgroundPrimary
        title = "Comprar"

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setStyle(.title3)
        titleLabel.textColor = .labelPrimary
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center
        titleLabel.text = "Compra en progreso"

        button.translatesAutoresizingMaskIntoConstraints = false
        button.setText("Volver a Invertir", .filled)
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
        s1.onLoadedBalances = { [weak self] balances in
            guard let self else { return }
            // NOTE: these are *market* tokens (from whitelist) and have 0 balances.
            // Payment balances are loaded from the gateway separately.
        }
        s1.onTokenSelected = { [weak self] token in
            self?.showEnterAmount(selectedToken: token)
        }

        let nav = UINavigationController(rootViewController: s1)
        nav.modalPresentationStyle = .pageSheet
        if #unavailable(iOS 15) {
            nav.navigationBar.backgroundColor = .backgroundSecondary
        }
        nav.presentationController?.delegate = self
        presenter?.present(nav, animated: true)
        navigationController = nav

        // Reuse the same balances payload that powers the Assets tab (single-safe or multivault aggregated).
        // This avoids reloading balances and keeps the buy flow consistent with what the user sees elsewhere.
        subscribeToBalances()

        // Try to use cached balances immediately; if none exist yet, do a one-time fetch mirroring Assets logic.
        applyFromCacheOrFetchIfNeeded()
    }

    private func showEnterAmount(selectedToken: TokenBalance) {
        let fiatCode = AppSettings.selectedFiatCode
        let s2 = InvestEnterAmountViewController(selectedToken: selectedToken,
                                                 paymentTotalFiat: paymentTotalFiat,
                                                 fiatCode: fiatCode,
                                                 paymentBalances: paymentBalances)
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
        // Avoid double-subscribe.
        if balancesObserver != nil { return }

        balancesObserver = NotificationCenter.default.addObserver(
            forName: .balanceUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let balances = notification.userInfo?["balances"] as? [TokenBalance] else { return }

            // Ignore "market" updates (Invertir tab posts zero-balance rows) — we only care about real balances.
            guard balances.contains(where: { $0.balanceValue.value > 0 }) else {
                #if DEBUG
                LogService.shared.debug("[InvestBuy][PaymentBalances] ignored balanceUpdated (no non-zero balances)")
                #endif
                return
            }

            LatestBalancesCache.shared.update(balances: balances)
            let payments = self.paymentBalancesFromAllBalances(balances)
            self.paymentBalances = payments
            self.paymentTotalFiat = payments.reduce(0) { $0 + $1.fiatValue }
            self.enterAmountViewController?.updatePaymentBalances(payments, totalFiat: self.paymentTotalFiat)

            #if DEBUG
            let sample = payments.prefix(25).map {
                "\($0.symbol){cat=\($0.category), amt=\($0.balanceFormatted5), fiat=\($0.fiatBalance)}"
            }.joined(separator: ", ")
            LogService.shared.debug("[InvestBuy][PaymentBalances] source=balanceUpdated payments=\(payments.count) sample[\(min(25, payments.count))]=[\(sample)]")
            #endif
        }
    }

    private func applyFromCacheOrFetchIfNeeded() {
        let cached = LatestBalancesCache.shared.balances
        if !cached.isEmpty {
            let payments = paymentBalancesFromAllBalances(cached)
            paymentBalances = payments
            paymentTotalFiat = payments.reduce(0) { $0 + $1.fiatValue }
            enterAmountViewController?.updatePaymentBalances(payments, totalFiat: paymentTotalFiat)
            #if DEBUG
            LogService.shared.debug("[InvestBuy][PaymentBalances] source=cache balances=\(cached.count) payments=\(payments.count)")
            #endif
            return
        }

        // No cache yet: trigger a one-time load using the same data source as Assets.
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
                #if DEBUG
                LogService.shared.debug("[InvestBuy][PaymentBalances] source=fallbackSingle balances=\(balances.count) payments=\(payments.count)")
                #endif
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
            #if DEBUG
            LogService.shared.debug("[InvestBuy][PaymentBalances] source=fallbackMulti balances=\(aggregated.balances.count) payments=\(payments.count)")
            #endif
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
            let sectionId = mapCategoryToSectionId(item)
            return sectionId == "savings" || sectionId == "moneymarket"
        }

        // Savings first, then money market, then by fiat desc and symbol.
        return filtered.sorted { lhs, rhs in
            func rank(_ item: TokenBalance) -> Int {
                mapCategoryToSectionId(item) == "moneymarket" ? 1 : 0
            }
            let lr = rank(lhs), rr = rank(rhs)
            if lr != rr { return lr < rr }
            if lhs.fiatValue != rhs.fiatValue { return lhs.fiatValue > rhs.fiatValue }
            return lhs.symbol.localizedCaseInsensitiveCompare(rhs.symbol) == .orderedAscending
        }
    }

    private func mapCategoryToSectionId(_ item: TokenBalance) -> String {
        let normalized = item.category
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")

        switch normalized {
        case "stablecoin", "stablecoins", "savings":
            return "savings"
        case "moneymarket":
            return "moneymarket"
        default:
            return "otros"
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

// MARK: - Shared balances cache (latest real balances, ignoring "market" lists)

final class LatestBalancesCache {
    static let shared = LatestBalancesCache()
    private init() {}

    private(set) var balances: [TokenBalance] = []

    func update(balances: [TokenBalance], allowAllZero: Bool = false) {
        // By default, only store if it looks like real balances (at least one non-zero amount),
        // to avoid accidentally caching "market" lists.
        if !allowAllZero {
            guard balances.contains(where: { $0.balanceValue.value > 0 }) else { return }
        }
        self.balances = balances
    }
}

