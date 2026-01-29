//
//  NoSafesViewController.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 21.10.20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import UIKit

class NoSafesViewController: ContainerViewController {
    var hasSafeViewController: UIViewController!
    var noSafeViewController: UIViewController!
    var safeDepolyingViewContoller: UIViewController!
    
    private var loadingViewController: UIViewController?
    private var errorViewController: UIViewController?
    private var isSyncing = false
    private var hasAttemptedSync = false

    var notificationCenter = NotificationCenter.default
    // preconditions
    //      hasSafeVC and noSafeVC are set
    override func viewDidLoad() {
        super.viewDidLoad()
        notificationCenter.addObserver(self, selector: #selector(reloadContent), name: .selectedSafeChanged, object: nil)
        notificationCenter.addObserver(self, selector: #selector(reloadContent), name: .selectedSafeUpdated, object: nil)

        reloadContent()
    }

    @objc private func reloadContent() {
        do {
            let safeOrNil = try Safe.getSelected()
            if let safe = safeOrNil {
                // Has safe - show normal content
                if safe.safeStatus == .deployed {
                    viewControllers = [hasSafeViewController]
                } else {
                    viewControllers = [safeDepolyingViewContoller]
                }
                displayChild(at: 0, in: view)
                return
            }
            
            // No safe found
            // If we haven't synced yet and not currently syncing, trigger sync
            if !hasAttemptedSync && !isSyncing && App.shared.authRepository.isAuthenticated() {
                startVaultSync()
            } else if isSyncing {
                // Sync in progress - show loading
                showLoadingState()
            } else if errorViewController != nil {
                // Sync failed - show error
                viewControllers = [errorViewController!]
                displayChild(at: 0, in: view)
            } else {
                // Sync completed but still no vaults - show "no vaults" message
                if hasAttemptedSync && !isSyncing && errorViewController == nil {
                    // Vaults were synced but none exist
                    if let loadSafeVC = noSafeViewController as? LoadSafeViewController {
                        loadSafeVC.showNoVaultsMessage = true
                    }
                } else {
                    // Reset to normal state if not showing post-sync message
                    if let loadSafeVC = noSafeViewController as? LoadSafeViewController {
                        loadSafeVC.showNoVaultsMessage = false
                    }
                }
                viewControllers = [noSafeViewController]
                displayChild(at: 0, in: view)
            }
        } catch {
            App.shared.snackbar.show(
                error: GSError.error(description: NSLocalizedString("ui_safe_failed_check_loaded_error", comment: "Failed to check loaded safes error"),
                                      error: error))
        }
    }
    
    private func startVaultSync() {
        guard !isSyncing else { return }
        isSyncing = true
        hasAttemptedSync = true
        
        VaultLogger.info("[NoSafesViewController] Starting vault sync (no safes found)")
        showLoadingState()
        
        App.shared.vaultsRepository.syncVaultsFromBackend(force: false) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isSyncing = false
                
                switch result {
                case .success:
                    VaultLogger.success("[NoSafesViewController] Vault sync completed successfully")
                    // Clear any error state
                    self.errorViewController = nil
                    // Re-check after sync - will show hasSafeViewController if vaults found
                    self.reloadContent()
                    
                case .failure(let error):
                    // Show error message
                    VaultLogger.error("[NoSafesViewController] Vault sync failed", error: error)
                    self.showErrorState(error: error)
                    // Still check if any safes exist (maybe some were cached)
                    self.reloadContent()
                }
            }
        }
    }
    
    private func showLoadingState() {
        if loadingViewController == nil {
            loadingViewController = VaultSyncLoadingViewController(
                message: "Cargando tus bóvedas"
            )
        }
        viewControllers = [loadingViewController!]
        displayChild(at: 0, in: view)
    }
    
    private func showErrorState(error: Error) {
        if errorViewController == nil {
            errorViewController = VaultSyncErrorViewController(
                message: "No hemos podido cargar tus bóvedas, por favor escribinos a hola@boveda.ai",
                showsSignOut: true
            )
        }
        viewControllers = [errorViewController!]
        displayChild(at: 0, in: view)
    }
}
