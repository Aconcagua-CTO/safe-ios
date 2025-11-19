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

        title = "Switch Safe Accounts"
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
            cell.setDetail(text: "Creating in progress...", style: .bodyTertiary)
            cell.setProgress(enabled: true)

        case .deploymentFailed:
            cell.setAddress(safe.addressValue, grayscale: true)
            cell.setDetail(text: "Failed to create", style: .bodyError)
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
            if !safe.isSelected {
                safe.select()
                didTapCloseButton()
            }
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

        let deleteAction = UIContextualAction(style: .destructive, title: "Remove") { [weak self] _, _, completion in
            self?.remove(safe: safe, sourceIndexPath: indexPath)
            completion(true)
        }
        actions.append(deleteAction)

        return UISwipeActionsConfiguration(actions: actions)
    }

    private func remove(safe: Safe, sourceIndexPath: IndexPath) {
        let title = safe.safeStatus == .deployed ?
        "Removing a Safe only removes it from this app. It does not delete the Safe from the blockchain. Funds will not get lost." :
        "Are you sure you want to remove this Safe? The transaction fees will not be returned."
        let alertController = UIAlertController(
            title: nil,
            message: title,
            preferredStyle: .multiplatformActionSheet)

        let remove = UIAlertAction(title: "Remove", style: .destructive) { _ in
            Safe.remove(safe: safe)
        }
        let cancel = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
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
            SnackbarViewController.show("Please log in before refreshing vaults.", duration: 3.0)
            return
        }
        
        guard !isManualVaultRefreshInProgress else {
            VaultLogger.debug("[Manual Refresh] Ignoring duplicate refresh request – already refreshing")
            SnackbarViewController.show("Vault refresh already in progress…", duration: 2.0)
            return
        }
        
        isManualVaultRefreshInProgress = true
        updateRefreshCellAppearance()
        VaultLogger.info("[Manual Refresh] User triggered vault refresh from SwitchSafesViewController")
        
        App.shared.vaultsRepository.syncVaultsFromBackend(force: true) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isManualVaultRefreshInProgress = false
                self.updateRefreshCellAppearance()
                
                switch result {
                case .success:
                    VaultLogger.success("[Manual Refresh] Vault refresh finished successfully")
                    SnackbarViewController.show("Vault list refreshed", duration: 3.0)
                    self.reloadData()
                case .failure(let error):
                    VaultLogger.error("[Manual Refresh] Vault refresh failed", error: error)
                    SnackbarViewController.show("Failed to refresh vaults: \(error.localizedDescription)", duration: 4.0)
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
