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
    private var localKeyRecoverViewController: LocalKeyRecoverViewController?
    private var generateKeyFlow: GenerateKeyFlow?
    private var tangemKeyFlow: TangemKeyFlow?

    private var isSyncing = false
    private var hasAttemptedSync = false
    private var isStartingGenerateKeyFlow = false
    private var isRegisteringOwnerKeys = false
    private var pendingGenerateKeyFlow = false

    private lazy var keysRegistrationService: KeysRegistrationService = {
        KeysRegistrationService(authRepository: App.shared.authRepository, logger: LogService.shared)
    }()

    var notificationCenter = NotificationCenter.default

    override func viewDidLoad() {
        super.viewDidLoad()

        notificationCenter.addObserver(self, selector: #selector(reloadContent), name: .selectedSafeChanged, object: nil)
        notificationCenter.addObserver(self, selector: #selector(reloadContent), name: .selectedSafeUpdated, object: nil)

        reloadContent()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if pendingGenerateKeyFlow && !isStartingGenerateKeyFlow {
            pendingGenerateKeyFlow = false
            startGenerateKeyFlow()
        }
    }

    @objc private func reloadContent() {
        // Non-blocking retry: if a previous registration attempt failed, try again opportunistically.
        attemptRegisterOwnerKeysIfNeeded(force: false)

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
                // Has vault(s). Gate on local keys.
                if !hasLocalOwnerKeysImportedOrGenerated() {
                    showLocalKeyRecoverState()
                    return
                }

                // Has vault(s) + local key(s) -> normal behavior
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
                // Sync completed but still no vaults: show pending activation screen.
                // This avoids showing the Load/Create Safe screen during onboarding.
                showPendingVaultActivationState()
                if !hasLocalOwnerKeysImportedOrGenerated() {
                    startGenerateKeyFlow()
                }
            } else {
                // Fallback (e.g. not authenticated)
                viewControllers = [noSafeViewController]
                displayChild(at: 0, in: view)
            }
        } catch {
            App.shared.snackbar.show(error: GSError.error(description: "Failed to check loaded safes", error: error))
        }
    }

    private func hasLocalOwnerKeysImportedOrGenerated() -> Bool {
        KeyInfo.count(.deviceImported) + KeyInfo.count(.deviceGenerated) > 0
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

    private func startGenerateKeyFlow() {
        guard !isStartingGenerateKeyFlow else { return }
        guard view.window != nil else {
            pendingGenerateKeyFlow = true
            return
        }
        isStartingGenerateKeyFlow = true

        let flow = GenerateKeyFlow { [weak self] success in
            guard let self else { return }
            // Release strong reference once the modal flow finishes/cancels.
            self.generateKeyFlow = nil
            self.isStartingGenerateKeyFlow = false
            // If the local owner key was added successfully, continue with Tangem card activation.
            // If user cancels/fails, just re-evaluate the gate.
            if success {
                self.startTangemKeyFlow()
            } else {
                self.reloadContent()
            }
        }
        // IMPORTANT: retain the flow, otherwise closures inside AddKeyFlow use `unowned self`
        // and can crash if the flow is deallocated while the UI is still visible.
        generateKeyFlow = flow

        // Present modally from current gate VC.
        present(flow: flow, dismissableOnSwipe: true)

        // If user completes successfully, `stop(success:)` will dismiss and call completion.
        // In that case, we reset the guard in completion via reloadContent after keys exist.
        // If flow is successful, the keys will exist and we won't re-enter this branch.
    }

    private func startTangemKeyFlow() {
        // Avoid double-presenting Tangem flow.
        guard tangemKeyFlow == nil else { return }

        let flow = TangemKeyFlow(service: TangemService.shared) { [weak self] success in
            guard let self else { return }
            self.tangemKeyFlow = nil
            if success {
                // Mark as pending and try to register immediately (non-blocking).
                AppSettings.pendingOwnerKeysRegistration = true
                self.attemptRegisterOwnerKeysIfNeeded(force: true)
            }
            // After Tangem card activation/import, proceed to the pending vault activation screen via normal gate evaluation.
            self.reloadContent()
        }
        tangemKeyFlow = flow
        present(flow: flow, dismissableOnSwipe: true)
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

    private func showLocalKeyRecoverState() {
        if localKeyRecoverViewController == nil {
            localKeyRecoverViewController = LocalKeyRecoverViewController()
        }
        viewControllers = [localKeyRecoverViewController!]
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
                message: "No hemos podido cargar tus bóvedas, por favor escribinos a hola@boveda.ai"
            )
        }
        viewControllers = [errorViewController!]
        displayChild(at: 0, in: view)
    }

    // MARK: - Owner key registration (deviceGenerated + tangem)

    private func attemptRegisterOwnerKeysIfNeeded(force: Bool) {
        guard App.shared.authRepository.isAuthenticated() else { return }
        guard force || AppSettings.pendingOwnerKeysRegistration else { return }
        guard !isRegisteringOwnerKeys else { return }

        let keys = collectOwnerKeysForRegistration()
        // Only register once we have both onboarding keys.
        guard keys.count >= 2 else { return }

        isRegisteringOwnerKeys = true
        keysRegistrationService.register(keys: keys) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRegisteringOwnerKeys = false
                switch result {
                case .success:
                    AppSettings.pendingOwnerKeysRegistration = false
                    LogService.shared.info("[KeysRegistration] owner keys registered successfully")
                case .failure(let error):
                    AppSettings.pendingOwnerKeysRegistration = true
                    LogService.shared.error("[KeysRegistration] failed to register owner keys", error: error)
                }
            }
        }
    }

    private func collectOwnerKeysForRegistration() -> [RegisterKey] {
        // Device-generated key (address only)
        let deviceKey: RegisterKey? = (try? KeyInfo.keys(types: [.deviceGenerated]))
            .flatMap { $0.first }
            .map { keyInfo in
                RegisterKey(keyType: "deviceGenerated",
                            address: keyInfo.address.checksummed,
                            cardId: nil,
                            walletIndex: nil)
            }

        // Tangem key (address + metadata)
        let tangemKey: RegisterKey? = (try? KeyInfo.keys(types: [.tangem]))
            .flatMap { $0.first }
            .flatMap { keyInfo in
                let metadata = keyInfo.metadata.flatMap { try? JSONDecoder().decode(KeyInfo.TangemKeyMetadata.self, from: $0) }
                return RegisterKey(keyType: "tangem",
                                   address: keyInfo.address.checksummed,
                                   cardId: metadata?.cardId,
                                   walletIndex: metadata?.walletIndex)
            }

        return [deviceKey, tangemKey].compactMap { $0 }
    }
}


