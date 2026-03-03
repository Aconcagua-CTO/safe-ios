//
//  VenderSelectAssetViewController.swift
//  Multisig
//
//  Created by Assistant on 29.12.25.
//

import UIKit
import CoreData

/// Screen 1 (Vender): select a token to sell.
/// - Shows owned tokens only (balance > 0)
/// - Only in categories: invest / cripto / oro
/// - Uses the same row UI style as the Assets screen (BalanceTableViewCell).
final class VenderSelectAssetViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    struct BalanceCategorySection {
        let id: String
        let title: String
        let items: [TokenBalance]
    }

    var onTokenSelected: ((TokenBalance) -> Void)?

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()

    private var sections: [BalanceCategorySection] = []
    private var currentDataTask: URLSessionTask?
    private var currentDataTasks: [URLSessionTask] = []

    private var clientGatewayService: BalancesAPI {
        guard let chain = try? Safe.getSelected()?.chain else {
            return App.shared.clientGatewayService
        }
        return chain.gatewayService()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .backgroundPrimary
        navigationItem.title = NSLocalizedString("ui_vender_select_asset_title", comment: "Vender select asset title")
        ViewControllerFactory.addCloseButton(self)

        configureTable()
        configureEmptyState()
        loadBalances()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        cancelRunningTasks()
    }

    private func configureTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .backgroundPrimary
        tableView.separatorColor = .separator
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }

        tableView.registerCell(BalanceTableViewCell.self)
        tableView.registerHeaderFooterView(BasicHeaderView.self)
        tableView.delegate = self
        tableView.dataSource = self

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureEmptyState() {
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.setStyle(.bodyPrimary)
        emptyLabel.textColor = .labelSecondary
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.text = NSLocalizedString("ui_assets_empty_title", comment: "Empty state title for assets")

        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
        emptyLabel.isHidden = true
    }

    private func showEmpty(_ isEmpty: Bool) {
        emptyLabel.isHidden = !isEmpty
        tableView.isHidden = isEmpty
    }

    private func loadBalances() {
        cancelRunningTasks()

        if AppSettings.multiVaultBalancesEnabled {
            loadMultiVaultBalances()
        } else {
            loadSingleVaultBalances()
        }
    }

    private func loadSingleVaultBalances() {
        guard let safe = try? Safe.getSelected(), let chainId = safe.chain?.id else {
            apply(balances: [])
            return
        }

        currentDataTask = clientGatewayService.asyncBalances(
            safeAddress: safe.addressValue,
            chainId: chainId
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .failure:
                    self.apply(balances: [])
                case .success(let summary):
                    let balances = summary.items.map { TokenBalance($0, code: AppSettings.selectedFiatCode, chainId: chainId) }
                    self.apply(balances: balances)
                }
            }
        }
    }

    private func loadMultiVaultBalances() {
        guard let safes = try? Safe.getActiveGroup() else {
            apply(balances: [])
            return
        }

        let deployedSafes = safes.filter { $0.safeStatus == .deployed }
        if deployedSafes.isEmpty {
            apply(balances: [])
            return
        }

        let group = DispatchGroup()
        let syncQueue = DispatchQueue(label: "io.gnosis.multisig.vender.multivault", qos: .userInitiated)
        var results: [(safeObjectID: NSManagedObjectID, chainId: String, summary: SafeBalanceSummary)] = []

        for safe in deployedSafes {
            guard let chain = safe.chain, let chainId = chain.id else { continue }
            group.enter()
            let service = chain.gatewayService()
            let task = service.asyncBalances(safeAddress: safe.addressValue, chainId: chainId) { [weak self] result in
                guard self != nil else { return }
                syncQueue.async {
                    if case .success(let summary) = result {
                        results.append((safeObjectID: safe.objectID, chainId: chainId, summary: summary))
                    }
                    group.leave()
                }
            }
            if let task {
                currentDataTasks.append(task)
            } else {
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.currentDataTasks.removeAll()
            if results.isEmpty {
                self.apply(balances: [])
                return
            }

            let aggregated = MultiVaultBalancesAggregator.aggregate(
                results.map { ($0.chainId, $0.summary) },
                fiatCode: AppSettings.selectedFiatCode
            )
            self.apply(balances: aggregated.balances)
        }
    }

    private func cancelRunningTasks() {
        currentDataTask?.cancel()
        currentDataTask = nil
        currentDataTasks.forEach { $0.cancel() }
        currentDataTasks.removeAll()
    }

    private func apply(balances: [TokenBalance]) {
        let sellable = balances
            .filter { $0.balanceValue.value > 0 }
            .filter { isSellableSectionId(mapCategoryToSectionId($0)) }

        sections = makeSellSections(items: sellable)
        tableView.reloadData()
        showEmpty(sections.allSatisfy { $0.items.isEmpty })
    }

    private func isSellableSectionId(_ id: String) -> Bool {
        [
            TokenCategory.sectionMoneyMarket,
            TokenCategory.sectionAcciones,
            TokenCategory.sectionEtfIndices,
            TokenCategory.sectionEtfOtros,
            TokenCategory.sectionCripto,
            TokenCategory.sectionOro,
            TokenCategory.sectionRootstock
        ].contains(id)
    }

    private var sellSectionOrder: [(id: String, title: String)] {
        [
            (id: TokenCategory.sectionMoneyMarket, title: "Money market"),
            (id: TokenCategory.sectionAcciones, title: "Acciones"),
            (id: TokenCategory.sectionEtfIndices, title: "ETF de indices"),
            (id: TokenCategory.sectionEtfOtros, title: "ETF otros"),
            (id: TokenCategory.sectionCripto, title: "Cripto"),
            (id: TokenCategory.sectionOro, title: "Oro"),
            (id: TokenCategory.sectionRootstock, title: "Rootstock"),
        ]
    }

    private func makeSellSections(items: [TokenBalance]) -> [BalanceCategorySection] {
        var grouped: [String: [TokenBalance]] = [:]
        for item in items {
            let sectionId = mapCategoryToSectionId(item)
            grouped[sectionId, default: []].append(item)
        }

        return sellSectionOrder.compactMap { entry in
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

    private func mapCategoryToSectionId(_ item: TokenBalance) -> String {
        TokenCategory.sectionId(for: item.category)
    }

    // MARK: UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = sections[indexPath.section].items[indexPath.row]
        let cell = tableView.dequeueCell(BalanceTableViewCell.self, for: indexPath)
        cell.setMainText(item.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
        cell.setDetailText(item.fiatBalance)
        cell.setSubDetailText(item.balanceFormatted5)
        cell.setBadge(text: nil)
        if let image = item.image {
            cell.setImage(image)
        } else {
            cell.setImage(with: item.imageURL, placeholder: UIImage(named: "ico-token-placeholder")!)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let view = tableView.dequeueHeaderFooterView(BasicHeaderView.self)
        view.setName(sections[section].title)
        return view
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        BasicHeaderView.headerHeight
    }

    // MARK: UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let token = sections[indexPath.section].items[indexPath.row]
        onTokenSelected?(token)
    }
}


