//
//  AssetsNoSafesGateViewController.swift
//  Multisig
//
//  Assets-tab-only gate that decides what to show after vault sync based on:
//  - whether vaults (safes) exist
//  - whether local owner keys exist (.deviceImported + .deviceGenerated)
//
//  Created by Cursor on 2026-01-07.
//

import UIKit

final class AssetsNoSafesGateViewController: ContainerViewController {
    var hasSafeViewController: UIViewController!
    var noSafeViewController: UIViewController!
    var safeDepolyingViewContoller: UIViewController!

    private var loadingViewController: UIViewController?
    private var errorViewController: UIViewController?

    private var pendingVaultActivationViewController: PendingVaultActivationViewController?

    private var isSyncing = false
    private var hasAttemptedSync = false

    var notificationCenter = NotificationCenter.default

    override func viewDidLoad() {
        super.viewDidLoad()

        notificationCenter.addObserver(self, selector: #selector(reloadContent), name: .selectedSafeChanged, object: nil)
        notificationCenter.addObserver(self, selector: #selector(reloadContent), name: .selectedSafeUpdated, object: nil)

        reloadContent()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    @objc private func reloadContent() {
        do {
            var selectedSafe = try Safe.getSelected()

            // If vaults exist but none is selected, select the first one so we can proceed.
            if selectedSafe == nil, Safe.countExcludingDemo > 0 {
                let allSafes = try Safe.getAll()
                if let first = allSafes.first {
                    first.select()
                    selectedSafe = first
                }
            }

            if let safe = selectedSafe {
                // Has vault(s) -> normal behavior
                if safe.safeStatus == .deployed {
                    viewControllers = [hasSafeViewController]
                } else {
                    viewControllers = [safeDepolyingViewContoller]
                }
                displayChild(at: 0, in: view)
                return
            }

            // No selected safe (and no safes in DB)
            if !hasAttemptedSync && !isSyncing && App.shared.authRepository.isAuthenticated() {
                startVaultSync()
            } else if isSyncing {
                showLoadingState()
            } else if errorViewController != nil {
                viewControllers = [errorViewController!]
                displayChild(at: 0, in: view)
            } else if hasAttemptedSync && !isSyncing && errorViewController == nil {
                showPendingVaultActivationState()
            } else {
                // Fallback (e.g. not authenticated)
                viewControllers = [noSafeViewController]
                displayChild(at: 0, in: view)
            }
        } catch {
            App.shared.snackbar.show(error: GSError.error(description: NSLocalizedString("ui_safe_failed_check_loaded_error", comment: "Failed to check loaded safes error"),
                                                          error: error))
        }
    }

    private func startVaultSync() {
        guard !isSyncing else { return }
        isSyncing = true
        hasAttemptedSync = true

        VaultLogger.info("[AssetsNoSafesGate] Starting vault sync (no safes found)")
        showLoadingState()

        App.shared.vaultsRepository.syncVaultsFromBackend(force: false) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSyncing = false

                switch result {
                case .success:
                    VaultLogger.success("[AssetsNoSafesGate] Vault sync completed successfully")
                    self.errorViewController = nil
                    self.reloadContent()
                case .failure(let error):
                    VaultLogger.error("[AssetsNoSafesGate] Vault sync failed", error: error)
                    self.showErrorState(error: error)
                    self.reloadContent()
                }
            }
        }
    }

    private func showPendingVaultActivationState() {
        if pendingVaultActivationViewController == nil {
            let vc = PendingVaultActivationViewController()
            vc.onVaultsRefreshed = { [weak self] in
                self?.reloadContent()
            }
            pendingVaultActivationViewController = vc
        }
        viewControllers = [pendingVaultActivationViewController!]
        displayChild(at: 0, in: view)
    }

    private func showLoadingState() {
        if loadingViewController == nil {
            loadingViewController = VaultSyncLoadingViewController(message: "Cargando tus bóvedas")
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

    // Owner key onboarding is now handled by the post-login gate coordinator.
}


