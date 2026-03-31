//
//  SwitchSafesViewController.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 30.10.20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import UIKit

final class SwitchSafesViewController: UITableViewController {
    var notificationCenter = NotificationCenter.default

    private var chainSafes = Chain.ChainSafes()
    private let refreshSection = 0
    private var isManualVaultRefreshInProgress = false

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("ui_safe_switch_title", comment: "Title for switching safes")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close, target: self, action: #selector(didTapCloseButton))
        
        if #unavailable(iOS 15) {
            // explicitly set background color to prevent transparent background in dark mode (iOS 14)
            navigationController?.navigationBar.backgroundColor = .backgroundSecondary
        }
        tableView.register(AddSafeTableViewCell.nib(), forCellReuseIdentifier: "AddSafe")
        tableView.register(SafeEntryTableViewCell.nib(), forCellReuseIdentifier: "SafeEntry")
        tableView.registerHeaderFooterView(NetworkIndicatorHeaderView.self)

        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }

        notificationCenter.addObserver(
            self, selector: #selector(reloadData), name: .selectedSafeChanged, object: nil)
        notificationCenter.addObserver(
            self, selector: #selector(reloadData), name: .selectedSafeUpdated, object: nil)

        reloadData()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Tracker.trackEvent(.safeSwitch)
    }

    @objc private func reloadData() {
        chainSafes = Chain.chainSafes()
        VaultLogger.debug("Reloaded chain safes: \(chainSafes.count) chain(s)")
        tableView.reloadData()
    }

    @objc override func closeModal() {
        // this will close this controller when the load Safe Account modal is closed
        presentingViewController?.dismiss(animated: true, completion: nil)
    }

    @objc private func didTapCloseButton() {
        dismiss(animated: true, completion: nil)
    }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        // Always include the manual refresh section at the top
        chainSafes.count + 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == refreshSection {
            return 1
        } else {
            let chainIndex = section - 1
            return chainSafes[chainIndex].safes.count
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == refreshSection {
            let cell = tableView.dequeueReusableCell(withIdentifier: "AddSafe", for: indexPath)
            (cell as? AddSafeTableViewCell)?.configureForRefresh(isRefreshing: isManualVaultRefreshInProgress)
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "SafeEntry", for: indexPath) as! SafeEntryTableViewCell
        let chainIndex = indexPath.section - 1
        let safe = chainSafes[chainIndex].safes[indexPath.row]
        cell.setName(safe.displayName)
        cell.setProgress(enabled: false)

        switch safe.safeStatus {
        case .deployed:
            cell.setAddress(safe.addressValue)
            cell.setDetail(address: safe.addressValue, prefix: safe.chain!.shortName)

        case .deploying, .indexing:
            cell.setAddress(safe.addressValue, grayscale: true)
            cell.setDetail(text: NSLocalizedString("ui_safe_creating_in_progress", comment: "Safe creation in progress"),
                           style: .bodyTertiary)
            cell.setProgress(enabled: true)

        case .deploymentFailed:
            cell.setAddress(safe.addressValue, grayscale: true)
            cell.setDetail(text: NSLocalizedString("ui_safe_failed_to_create", comment: "Safe failed to create"),
                           style: .bodyError)
        }

        cell.setSelection(safe.isSelected)
        return cell
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        indexPath.section == refreshSection ? 54 : 66
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == refreshSection {
            refreshVaultList()
        } else {
            let chainIndex = indexPath.section - 1
            let safe = chainSafes[chainIndex].safes[indexPath.row]
            safe.select()
            didTapCloseButton()
        }
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section != refreshSection else { return nil }

        let view = tableView.dequeueHeaderFooterView(NetworkIndicatorHeaderView.self)
        let chainIndex = section - 1
        let chain = chainSafes[chainIndex].chain
        view.text = chain.name
        view.dotColor = chain.backgroundColor
        return view
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        section == refreshSection ? 0 : NetworkIndicatorHeaderView.height
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        indexPath.section != refreshSection
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section != refreshSection else { return nil }
        let chainIndex = indexPath.section - 1
        let safe = chainSafes[chainIndex].safes[indexPath.row]

        var actions = [UIContextualAction]()

        let deleteAction = UIContextualAction(style: .destructive,
                                              title: NSLocalizedString("ui_safe_remove_action", comment: "Remove safe action")) { [weak self] _, _, completion in
            self?.remove(safe: safe, sourceIndexPath: indexPath)
            completion(true)
        }
        actions.append(deleteAction)

        return UISwipeActionsConfiguration(actions: actions)
    }

    private func remove(safe: Safe, sourceIndexPath: IndexPath) {
        let title = safe.safeStatus == .deployed
            ? NSLocalizedString("ui_safe_remove_message_ready", comment: "Remove safe message when created")
            : NSLocalizedString("ui_safe_remove_message_not_ready", comment: "Remove safe message when creating")
        let alertController = UIAlertController(
            title: nil,
            message: title,
            preferredStyle: .multiplatformActionSheet)

        let remove = UIAlertAction(title: NSLocalizedString("ui_safe_remove_action", comment: "Remove safe action"),
                                   style: .destructive) { _ in
            Safe.remove(safe: safe)
        }
        let cancel = UIAlertAction(title: NSLocalizedString("cancel", comment: "Cancel action title"),
                                   style: .cancel,
                                   handler: nil)
        alertController.addAction(remove)
        alertController.addAction(cancel)
        
        if let popoverPresentationController = alertController.popoverPresentationController {
            popoverPresentationController.sourceView = tableView
            popoverPresentationController.sourceRect = tableView.rectForRow(at: sourceIndexPath)
        }
        
        self.present(alertController, animated: true)
    }
    
    private func refreshVaultList() {
        guard App.shared.authRepository.isAuthenticated() else {
            VaultLogger.warning("[Manual Refresh] User attempted to refresh vaults without authentication")
            SnackbarViewController.show(NSLocalizedString("ui_safe_refresh_login_required", comment: "Login required to refresh vaults"),
                                        duration: 3.0)
            return
        }
        
        guard !isManualVaultRefreshInProgress else {
            VaultLogger.debug("[Manual Refresh] Ignoring duplicate refresh request – already refreshing")
            SnackbarViewController.show(NSLocalizedString("ui_safe_refresh_in_progress", comment: "Vault refresh in progress"),
                                        duration: 2.0)
            return
        }
        
        isManualVaultRefreshInProgress = true
        updateRefreshCellAppearance()
        VaultLogger.info("[Manual Refresh] User triggered vault refresh from SwitchSafesViewController")
        VaultLogger.info("[Manual Refresh] Refreshing chain registry before vault sync")

        ChainManager.updateChainsInfo { [weak self] chainResult in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch chainResult {
                case .success(let count):
                    VaultLogger.success("[Manual Refresh] Chain registry refreshed (\(count) chain(s))")
                case .failure(let error):
                    VaultLogger.warning("[Manual Refresh] Chain registry refresh failed: \(error.localizedDescription)")
                }

                App.shared.vaultsRepository.syncVaultsFromBackend(force: true) { [weak self] result in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        self.isManualVaultRefreshInProgress = false
                        self.updateRefreshCellAppearance()

                        switch result {
                        case .success:
                            VaultLogger.success("[Manual Refresh] Vault refresh finished successfully")
                            SnackbarViewController.show(NSLocalizedString("ui_safe_refresh_success", comment: "Vault refresh success"),
                                                        duration: 3.0)
                            // Also refresh token whitelist
                            LogService.shared.info("[Manual Refresh] Triggering token whitelist sync")
                            App.shared.tokenWhitelistRepository.syncWhitelist(force: true, network: nil) { whitelistResult in
                                if case .failure(let error) = whitelistResult {
                                    LogService.shared.error("[Manual Refresh] Whitelist sync failed: \(error.localizedDescription)")
                                } else {
                                    LogService.shared.info("[Manual Refresh] Whitelist sync completed")
                                }
                            }
                            // Also refresh transaction names
                            LogService.shared.info("[Manual Refresh] Triggering transaction names sync")
                            App.shared.transactionNamesRepository.syncTransactionNames(force: true) { namesResult in
                                if case .failure(let error) = namesResult {
                                    LogService.shared.error("[Manual Refresh] Transaction names sync failed: \(error.localizedDescription)")
                                } else {
                                    LogService.shared.info("[Manual Refresh] Transaction names sync completed")
                                }
                            }
                            self.reloadData()
                        case .failure(let error):
                            VaultLogger.error("[Manual Refresh] Vault refresh failed", error: error)
                            SnackbarViewController.show(String(format: NSLocalizedString("ui_safe_refresh_failed_format", comment: "Vault refresh failed format"),
                                                               error.localizedDescription),
                                                        duration: 4.0)
                        }
                    }
                }
            }
        }
    }
    
    private func updateRefreshCellAppearance() {
        guard let cell = tableView.cellForRow(at: IndexPath(row: 0, section: refreshSection)) as? AddSafeTableViewCell else {
            return
        }
        cell.configureForRefresh(isRefreshing: isManualVaultRefreshInProgress)
    }
}

final class GroupedSwitchSafesViewController: UITableViewController {
    struct GroupedVaultEntry {
        let address: Address
        let primarySafe: Safe
        let safes: [Safe]
        let networkShortNames: [String]
        let isSelected: Bool
    }

    var notificationCenter = NotificationCenter.default

    private var ownEntries: [GroupedVaultEntry] = []
    private var delegateEntries: [GroupedVaultEntry] = []
    private let refreshSection = 0
    private let ownSection = 1
    private let delegateSection = 2
    private var isManualVaultRefreshInProgress = false
    private var isVaultNameUpdateInProgress = false
    private lazy var vaultsService = VaultsService(
        authRepository: App.shared.authRepository,
        logger: LogService.shared
    )

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("ui_safe_switch_title", comment: "Title for switching safes")
        configureNavigationControls()

        if #unavailable(iOS 15) {
            // explicitly set background color to prevent transparent background in dark mode (iOS 14)
            navigationController?.navigationBar.backgroundColor = .backgroundSecondary
        }
        tableView.register(AddSafeTableViewCell.nib(), forCellReuseIdentifier: "AddSafe")
        tableView.register(SafeEntryTableViewCell.nib(), forCellReuseIdentifier: "SafeEntry")
        tableView.registerCell(DetailAccountCell.self)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 66

        let pullToRefresh = UIRefreshControl()
        pullToRefresh.addTarget(self, action: #selector(didPullToRefresh), for: .valueChanged)
        refreshControl = pullToRefresh

        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }

        notificationCenter.addObserver(
            self, selector: #selector(reloadData), name: .selectedSafeChanged, object: nil)
        notificationCenter.addObserver(
            self, selector: #selector(reloadData), name: .selectedSafeUpdated, object: nil)

        reloadData()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        configureNavigationControls()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Tracker.trackEvent(.safeSwitch)
    }

    @objc private func reloadData() {
        ownEntries = buildGroupedEntries(from: (try? Safe.getOwnVaults()) ?? [])
        delegateEntries = buildGroupedEntries(from: (try? Safe.getDelegateVaults()) ?? [])
        VaultLogger.debug("Reloaded grouped safes: own=\(ownEntries.count), delegate=\(delegateEntries.count)")
        tableView.reloadData()
    }

    @objc override func closeModal() {
        exitVaultList()
    }

    @objc private func didTapCloseButton() {
        exitVaultList()
    }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        // Always include the manual refresh section at the top
        delegateEntries.isEmpty ? 2 : 3
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == refreshSection {
            return 1
        }
        if section == ownSection {
            return ownEntries.count
        }
        if section == delegateSection {
            return delegateEntries.count
        }
        return 0
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == refreshSection {
            let cell = tableView.dequeueReusableCell(withIdentifier: "AddSafe", for: indexPath)
            (cell as? AddSafeTableViewCell)?.configureForRefresh(isRefreshing: isManualVaultRefreshInProgress)
            return cell
        }

        guard let entry = entryForListSection(at: indexPath) else {
            return UITableViewCell()
        }
        let safe = entry.primarySafe
        let isDelegateSection = indexPath.section == delegateSection

        switch safe.safeStatus {
        case .deployed:
            return deployedEntryCell(for: indexPath, entry: entry, isDelegateSection: isDelegateSection)

        case .deploying, .indexing:
            let cell = tableView.dequeueReusableCell(withIdentifier: "SafeEntry", for: indexPath) as! SafeEntryTableViewCell
            cell.setName(displayTitle(for: entry))
            cell.setProgress(enabled: false)
            cell.setAddress(entry.address, grayscale: true)
            cell.setDetail(text: NSLocalizedString("ui_safe_creating_in_progress", comment: "Safe creation in progress"),
                           style: .bodyTertiary)
            cell.setProgress(enabled: true)
            cell.setSelection(entry.isSelected)
            cell.accessoryView = accessoryMenuView(for: entry, allowsRename: indexPath.section == ownSection)
            return cell

        case .deploymentFailed:
            let cell = tableView.dequeueReusableCell(withIdentifier: "SafeEntry", for: indexPath) as! SafeEntryTableViewCell
            cell.setName(displayTitle(for: entry))
            cell.setProgress(enabled: false)
            cell.setAddress(entry.address, grayscale: true)
            cell.setDetail(text: NSLocalizedString("ui_safe_failed_to_create", comment: "Safe failed to create"),
                           style: .bodyError)
            cell.setSelection(entry.isSelected)
            cell.accessoryView = accessoryMenuView(for: entry, allowsRename: indexPath.section == ownSection)
            return cell
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        indexPath.section == refreshSection ? 54 : UITableView.automaticDimension
    }

    override func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        indexPath.section == refreshSection ? 54 : 66
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == refreshSection {
            refreshVaultList()
        } else if let entry = entryForListSection(at: indexPath) {
            AppSettings.activeVaultGroupAddress = entry.address.checksummed
            entry.primarySafe.select()
            exitVaultList()
        }
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section != refreshSection else { return nil }
        guard section == ownSection || section == delegateSection else { return nil }

        let title = section == ownSection ? "Mis Bovedas" : "Bovedas Delegadas"

        let container = UIView()
        container.backgroundColor = .clear

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize, weight: .semibold)
        label.textColor = .labelSecondary
        label.text = title
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4)
        ])

        return container
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        section == refreshSection ? 0 : 28
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        indexPath.section == ownSection
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section == ownSection, let entry = entryForListSection(at: indexPath) else { return nil }
        
        let editAction = UIContextualAction(
            style: .normal,
            title: NSLocalizedString("button_edit", comment: "Edit action title")
        ) { [weak self] _, _, completion in
            self?.showRename(for: entry)
            completion(true)
        }
        editAction.backgroundColor = .primary

        let deleteAction = UIContextualAction(style: .destructive,
                                              title: NSLocalizedString("ui_safe_remove_action", comment: "Remove safe action")) { [weak self] _, _, completion in
            self?.remove(safes: entry.safes, sourceIndexPath: indexPath)
            completion(true)
        }

        return UISwipeActionsConfiguration(actions: [deleteAction, editAction])
    }

    private func showRename(for entry: GroupedVaultEntry) {
        LogService.shared.info("[VaultRename] Opening rename screen for address=\(entry.address.checksummed)")
        let editSafeNameViewController = EditSafeNameViewController()
        editSafeNameViewController.name = initialVaultName(for: entry)
        editSafeNameViewController.completion = { [weak self] name in
            LogService.shared.info("[VaultRename] Rename completion received for address=\(entry.address.checksummed) value='\(name)'")
            self?.renameVaultGroup(entry: entry, vaultName: name)
        }
        show(editSafeNameViewController, sender: self)
    }

    @objc private func didPullToRefresh() {
        refreshVaultList()
    }

    private func renameVaultGroup(entry: GroupedVaultEntry, vaultName: String) {
        let trimmed = vaultName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isVaultNameUpdateInProgress else {
            SnackbarViewController.show("Vault name update in progress…", duration: 2.0)
            return
        }

        let targets = entry.safes.map(vaultIdCandidates(for:)).filter { !$0.isEmpty }
        LogService.shared.info("[VaultRename] Requested rename to '\(trimmed)' for address=\(entry.address.checksummed)")
        LogService.shared.debug("[VaultRename] Candidate vault ids: \(targets.flatMap { $0 }.joined(separator: ", "))")
        guard !targets.isEmpty else {
            SnackbarViewController.show("Unable to identify vault for rename.", duration: 3.0)
            return
        }

        isVaultNameUpdateInProgress = true

        var firstError: Error?
        let group = DispatchGroup()
        for vaultIds in targets {
            group.enter()
            updateVaultNameWithFallback(vaultIds: vaultIds, vaultName: trimmed) { result in
                if case .failure(let error) = result, firstError == nil {
                    firstError = error
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.isVaultNameUpdateInProgress = false
            if let error = firstError {
                LogService.shared.error("[VaultRename] Failed to update vault name for group \(entry.address.checksummed)", error: error)
                SnackbarViewController.show(
                    "Failed to update vault name: \(error.localizedDescription)",
                    duration: 4.0
                )
                return
            }

            entry.safes.forEach { $0.vaultName = trimmed }
            App.shared.coreDataStack.saveContext()
            self.notificationCenter.post(name: .selectedSafeUpdated, object: nil)
            self.navigationController?.popViewController(animated: true)
            SnackbarViewController.show("Vault name updated.", duration: 2.0)
            LogService.shared.info("[VaultRename] Local vaultName updated for \(entry.safes.count) safe(s)")
            self.reloadData()
        }
    }

    private func remove(safes: [Safe], sourceIndexPath: IndexPath) {
        let hasDeployed = safes.contains(where: { $0.safeStatus == .deployed })
        let title = hasDeployed
            ? NSLocalizedString("ui_safe_remove_message_ready", comment: "Remove safe message when created")
            : NSLocalizedString("ui_safe_remove_message_not_ready", comment: "Remove safe message when creating")
        let alertController = UIAlertController(
            title: nil,
            message: title,
            preferredStyle: .multiplatformActionSheet)

        let remove = UIAlertAction(title: NSLocalizedString("ui_safe_remove_action", comment: "Remove safe action"),
                                   style: .destructive) { _ in
            safes.forEach { Safe.remove(safe: $0) }
        }
        let cancel = UIAlertAction(title: NSLocalizedString("cancel", comment: "Cancel action title"),
                                   style: .cancel,
                                   handler: nil)
        alertController.addAction(remove)
        alertController.addAction(cancel)

        if let popoverPresentationController = alertController.popoverPresentationController {
            popoverPresentationController.sourceView = tableView
            popoverPresentationController.sourceRect = tableView.rectForRow(at: sourceIndexPath)
        }

        present(alertController, animated: true)
    }

    private func refreshVaultList() {
        guard App.shared.authRepository.isAuthenticated() else {
            VaultLogger.warning("[Manual Refresh] User attempted to refresh vaults without authentication")
            SnackbarViewController.show(NSLocalizedString("ui_safe_refresh_login_required", comment: "Login required to refresh vaults"),
                                        duration: 3.0)
            refreshControl?.endRefreshing()
            return
        }

        guard !isManualVaultRefreshInProgress else {
            VaultLogger.debug("[Manual Refresh] Ignoring duplicate refresh request – already refreshing")
            SnackbarViewController.show(NSLocalizedString("ui_safe_refresh_in_progress", comment: "Vault refresh in progress"),
                                        duration: 2.0)
            refreshControl?.endRefreshing()
            return
        }

        isManualVaultRefreshInProgress = true
        updateRefreshCellAppearance()
        VaultLogger.info("[Manual Refresh] User triggered vault refresh from GroupedSwitchSafesViewController")
        VaultLogger.info("[Manual Refresh] Refreshing chain registry before vault sync")

        ChainManager.updateChainsInfo { [weak self] chainResult in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch chainResult {
                case .success(let count):
                    VaultLogger.success("[Manual Refresh] Chain registry refreshed (\(count) chain(s))")
                case .failure(let error):
                    VaultLogger.warning("[Manual Refresh] Chain registry refresh failed: \(error.localizedDescription)")
                }

                App.shared.vaultsRepository.syncVaultsFromBackend(force: true) { [weak self] result in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        self.isManualVaultRefreshInProgress = false
                        self.updateRefreshCellAppearance()
                        self.refreshControl?.endRefreshing()

                        switch result {
                        case .success:
                            VaultLogger.success("[Manual Refresh] Vault refresh finished successfully")
                            SnackbarViewController.show(NSLocalizedString("ui_safe_refresh_success", comment: "Vault refresh success"),
                                                        duration: 3.0)
                            // Also refresh token whitelist
                            LogService.shared.info("[Manual Refresh] Triggering token whitelist sync")
                            App.shared.tokenWhitelistRepository.syncWhitelist(force: true, network: nil) { whitelistResult in
                                if case .failure(let error) = whitelistResult {
                                    LogService.shared.error("[Manual Refresh] Whitelist sync failed: \(error.localizedDescription)")
                                } else {
                                    LogService.shared.info("[Manual Refresh] Whitelist sync completed")
                                }
                            }
                            // Also refresh transaction names
                            LogService.shared.info("[Manual Refresh] Triggering transaction names sync")
                            App.shared.transactionNamesRepository.syncTransactionNames(force: true) { namesResult in
                                if case .failure(let error) = namesResult {
                                    LogService.shared.error("[Manual Refresh] Transaction names sync failed: \(error.localizedDescription)")
                                } else {
                                    LogService.shared.info("[Manual Refresh] Transaction names sync completed")
                                }
                            }
                            self.reloadData()
                        case .failure(let error):
                            VaultLogger.error("[Manual Refresh] Vault refresh failed", error: error)
                            SnackbarViewController.show(String(format: NSLocalizedString("ui_safe_refresh_failed_format", comment: "Vault refresh failed format"),
                                                               error.localizedDescription),
                                                        duration: 4.0)
                        }
                    }
                }
            }
        }
    }

    private func updateRefreshCellAppearance() {
        guard let cell = tableView.cellForRow(at: IndexPath(row: 0, section: refreshSection)) as? AddSafeTableViewCell else {
            return
        }
        cell.configureForRefresh(isRefreshing: isManualVaultRefreshInProgress)
    }

    private func configureNavigationControls() {
        if isPresentedAsModalRoot() {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .close,
                target: self,
                action: #selector(didTapCloseButton)
            )
        } else {
            navigationItem.leftBarButtonItem = nil
        }
    }

    private func isPresentedAsModalRoot() -> Bool {
        guard let nav = navigationController else {
            return presentingViewController != nil
        }
        return nav.viewControllers.first === self && nav.presentingViewController != nil
    }

    private func exitVaultList() {
        if let nav = navigationController {
            if nav.viewControllers.first === self {
                if nav.presentingViewController != nil {
                    nav.dismiss(animated: true)
                    return
                }
            } else {
                nav.popViewController(animated: true)
                return
            }
        }
        dismiss(animated: true)
    }

    private func deployedEntryCell(for indexPath: IndexPath, entry: GroupedVaultEntry, isDelegateSection: Bool) -> DetailAccountCell {
        let cell = tableView.dequeueCell(DetailAccountCell.self, for: indexPath)
        let networkLine = networkPrefixesLine(for: entry, isDelegateSection: isDelegateSection)
        let browseURL = entry.primarySafe.chain?.browserURL(address: entry.address.checksummed)
        cell.setAccount(address: entry.address,
                        label: displayTitle(for: entry),
                        copyEnabled: true,
                        browseURL: browseURL,
                        prefix: nil,
                        networkPrefixes: networkLine,
                        showAccessoryImage: false)
        cell.accessoryView = accessoryMenuView(for: entry, allowsRename: !isDelegateSection)
        return cell
    }

    private func accessoryMenuView(for entry: GroupedVaultEntry, allowsRename: Bool) -> UIView? {
        let isSelected = entry.isSelected
        guard allowsRename || isSelected else { return nil }
        let containerWidth: CGFloat = allowsRename && isSelected ? 56 : 28
        let containerHeight: CGFloat = 28
        let container = UIView(frame: CGRect(x: 0, y: 0, width: containerWidth, height: containerHeight))
        container.backgroundColor = .clear

        if isSelected {
            let checkmarkView = UIImageView(frame: CGRect(x: 0, y: 4, width: 20, height: 20))
            checkmarkView.image = UIImage(systemName: "checkmark")
            checkmarkView.tintColor = .primary
            checkmarkView.contentMode = .scaleAspectFit
            container.addSubview(checkmarkView)
        }

        if allowsRename {
            let renameAction = UIAction(title: NSLocalizedString("button_edit", comment: "Edit action title")) { [weak self] _ in
                self?.showRename(for: entry)
            }
            let buttonX: CGFloat = isSelected ? 28 : 0
            let button = UIButton(type: .system)
            button.frame = CGRect(x: buttonX, y: 0, width: 28, height: 28)
            button.setImage(UIImage(systemName: "ellipsis"), for: .normal)
            button.tintColor = .icon
            button.menu = UIMenu(children: [renameAction])
            button.showsMenuAsPrimaryAction = true
            container.addSubview(button)
        }

        return container
    }

    private func networkPrefixesLine(for entry: GroupedVaultEntry, isDelegateSection: Bool) -> String? {
        let networks = entry.networkShortNames.joined(separator: ", ")
        let ownerText = isDelegateSection ? (entry.primarySafe.ownerName ?? entry.primarySafe.displayName) : nil

        if let ownerText, !ownerText.isEmpty, !networks.isEmpty {
            return "\(ownerText) · \(networks)"
        }
        if let ownerText, !ownerText.isEmpty {
            return ownerText
        }
        return networks.isEmpty ? nil : networks
    }

    private func initialVaultName(for entry: GroupedVaultEntry) -> String {
        if let current = entry.safes.first(where: { $0.chain?.id == "1" })?.vaultName,
           !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return current
        }
        if let current = entry.primarySafe.vaultName,
           !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return current
        }
        return displayTitle(for: entry)
    }

    private func vaultIdCandidates(for safe: Safe) -> [String] {
        var candidates: [String] = []
        let address = safe.addressValue
        candidates.append(address.checksummed)
        let lowercaseHex = address.hexadecimal.lowercased()
        candidates.append(lowercaseHex.hasPrefix("0x") ? lowercaseHex : "0x\(lowercaseHex)")
        if let rawAddress = safe.address, !rawAddress.isEmpty {
            candidates.append(rawAddress)
        }
        if let chainId = safe.chain?.id,
           let network = TransactionRequestsService.networkName(forChainId: chainId) {
            candidates.append("\(network):\(lowercaseHex)")
        }
        var unique: [String] = []
        for id in candidates where !unique.contains(id) {
            unique.append(id)
        }
        return unique
    }

    private func updateVaultNameWithFallback(
        vaultIds: [String],
        vaultName: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        func attempt(_ index: Int, lastError: Error? = nil) {
            guard index < vaultIds.count else {
                completion(.failure(lastError ?? NSError(domain: "VaultRename", code: -1, userInfo: nil)))
                return
            }
            vaultsService.updateVaultNameForCurrentSession(vaultId: vaultIds[index], vaultName: vaultName) { result in
                switch result {
                case .success:
                    completion(.success(()))
                case .failure(let error):
                    attempt(index + 1, lastError: error)
                }
            }
        }
        attempt(0)
    }

    private func buildGroupedEntries(from safes: [Safe]) -> [GroupedVaultEntry] {
        let grouped = Dictionary(grouping: safes) { safe in
            safe.address?.lowercased() ?? ""
        }

        var entries: [GroupedVaultEntry] = []
        entries.reserveCapacity(grouped.count)

        for (addressKey, groupedSafes) in grouped where !addressKey.isEmpty {
            let safesWithChain = groupedSafes.filter { $0.chain?.id != nil && $0.address != nil }
            guard !safesWithChain.isEmpty else { continue }

            let primarySafe = safesWithChain.min { chainIdValue(for: $0) < chainIdValue(for: $1) }!
            let address = primarySafe.addressValue

            let sortedSafes = safesWithChain.sorted { chainIdValue(for: $0) < chainIdValue(for: $1) }
            var seenShortNames = Set<String>()
            let networkShortNames = sortedSafes.compactMap { safe -> String? in
                guard let shortName = safe.chain?.shortName else { return nil }
                guard !seenShortNames.contains(shortName) else { return nil }
                seenShortNames.insert(shortName)
                return shortName
            }

            let isSelected: Bool = {
                guard let activeAddress = AppSettings.activeVaultGroupAddress?.lowercased(), !activeAddress.isEmpty else {
                    return safesWithChain.contains(where: { $0.isSelected })
                }
                return addressKey == activeAddress
            }()

            entries.append(GroupedVaultEntry(
                address: address,
                primarySafe: primarySafe,
                safes: safesWithChain,
                networkShortNames: networkShortNames,
                isSelected: isSelected
            ))
        }

        return entries.sorted { lhs, rhs in
            if lhs.isSelected != rhs.isSelected {
                return lhs.isSelected
            }
            let lhsDate = lhs.primarySafe.additionDate ?? .distantPast
            let rhsDate = rhs.primarySafe.additionDate ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.address.description.lowercased() < rhs.address.description.lowercased()
        }
    }

    /// Title for the vault group cell: "firstName - vaultName" when the Ethereum vault in the group has a custom vaultName; otherwise just the base display name.
    /// When a custom vaultName exists, the base is the user's first name (from auth), not the Safe's name (which the backend sets to vaultName), to avoid showing the vault name twice.
    private func displayTitle(for entry: GroupedVaultEntry) -> String {
        guard let ethSafe = entry.safes.first(where: { $0.chain?.id == "1" }),
              let vaultName = ethSafe.vaultName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !vaultName.isEmpty
        else {
            return entry.primarySafe.displayName
        }
        let firstName = currentUserFirstName() ?? entry.primarySafe.displayName
        return "\(firstName) - \(vaultName)"
    }

    /// User's first name from auth display name (e.g. "Manuel R" → "Manuel"), for use as the base in "firstName - vaultName" when the vault has a custom name.
    private func currentUserFirstName() -> String? {
        guard let displayName = App.shared.authRepository.getCurrentUser()?.displayName else {
            return nil
        }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
    }

    private func detailText(for entry: GroupedVaultEntry, isDelegateSection: Bool) -> String {
        let addressText = entry.address.ellipsized()
        let networks = entry.networkShortNames.joined(separator: ", ")
        let ownerText = isDelegateSection ? (entry.primarySafe.ownerName ?? entry.primarySafe.displayName) : nil

        var detailLines: [String] = [addressText]
        if let ownerText, !ownerText.isEmpty {
            detailLines.append(ownerText)
        }
        if !networks.isEmpty {
            detailLines.append(networks)
        }
        return detailLines.joined(separator: "\n")
    }

    private func entryForListSection(at indexPath: IndexPath) -> GroupedVaultEntry? {
        switch indexPath.section {
        case ownSection:
            guard ownEntries.indices.contains(indexPath.row) else { return nil }
            return ownEntries[indexPath.row]
        case delegateSection:
            guard delegateEntries.indices.contains(indexPath.row) else { return nil }
            return delegateEntries[indexPath.row]
        default:
            return nil
        }
    }

    private func chainIdValue(for safe: Safe) -> UInt64 {
        guard let chainId = safe.chain?.id, let numericId = UInt64(chainId) else {
            return UInt64.max
        }
        return numericId
    }
}
