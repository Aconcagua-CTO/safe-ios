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

    private var groupedEntries: [GroupedVaultEntry] = []
    private let refreshSection = 0
    private let listSection = 1
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
        groupedEntries = buildGroupedEntries()
        VaultLogger.debug("Reloaded grouped safes: \(groupedEntries.count) entry(ies)")
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
        listSection + 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == refreshSection {
            return 1
        }
        return groupedEntries.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == refreshSection {
            let cell = tableView.dequeueReusableCell(withIdentifier: "AddSafe", for: indexPath)
            (cell as? AddSafeTableViewCell)?.configureForRefresh(isRefreshing: isManualVaultRefreshInProgress)
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "SafeEntry", for: indexPath) as! SafeEntryTableViewCell
        let entry = groupedEntries[indexPath.row]
        let safe = entry.primarySafe
        cell.setName(safe.displayName)
        cell.setProgress(enabled: false)

        switch safe.safeStatus {
        case .deployed:
            cell.setAddress(entry.address)
            cell.setDetail(text: detailText(for: entry), style: .bodyTertiary)

        case .deploying, .indexing:
            cell.setAddress(entry.address, grayscale: true)
            cell.setDetail(text: NSLocalizedString("ui_safe_creating_in_progress", comment: "Safe creation in progress"),
                           style: .bodyTertiary)
            cell.setProgress(enabled: true)

        case .deploymentFailed:
            cell.setAddress(entry.address, grayscale: true)
            cell.setDetail(text: NSLocalizedString("ui_safe_failed_to_create", comment: "Safe failed to create"),
                           style: .bodyError)
        }

        cell.setSelection(entry.isSelected)
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
            let entry = groupedEntries[indexPath.row]
            entry.primarySafe.select()
            didTapCloseButton()
        }
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        nil
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        0
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        indexPath.section != refreshSection
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section != refreshSection else { return nil }
        let entry = groupedEntries[indexPath.row]

        let deleteAction = UIContextualAction(style: .destructive,
                                              title: NSLocalizedString("ui_safe_remove_action", comment: "Remove safe action")) { [weak self] _, _, completion in
            self?.remove(safes: entry.safes, sourceIndexPath: indexPath)
            completion(true)
        }

        return UISwipeActionsConfiguration(actions: [deleteAction])
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

    private func buildGroupedEntries() -> [GroupedVaultEntry] {
        guard let safes = try? Safe.getAll() else { return [] }

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

            let isSelected = safesWithChain.contains(where: { $0.isSelected })

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

    private func detailText(for entry: GroupedVaultEntry) -> String {
        let addressText = entry.address.ellipsized()
        let networks = entry.networkShortNames.joined(separator: ", ")
        if networks.isEmpty {
            return addressText
        }
        return "\(addressText)\n\(networks)"
    }

    private func chainIdValue(for safe: Safe) -> UInt64 {
        guard let chainId = safe.chain?.id, let numericId = UInt64(chainId) else {
            return UInt64.max
        }
        return numericId
    }
}
