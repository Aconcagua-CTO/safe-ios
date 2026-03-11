//
//  PostLoginGateCoordinator.swift
//  Multisig
//
//  Created by Cursor on 2026-01-21.
//

import UIKit

final class PostLoginGateCoordinator: NSObject, UIAdaptivePresentationControllerDelegate {
    private weak var sceneDelegate: SceneDelegate?
    private var completion: (() -> Void)?

    private var gateViewController: PostLoginGateViewController?
    private var gateNavigationController: UINavigationController?
    private var hasAttemptedVaultSync = false
    private var isSyncingVaults = false
    private var isSignUp: Bool
    private var isPresentingFlow = false
    private var isProvisioningCardKey = false
    private var isShowingPostSignupInstructions = false
    private var lastCardKeyAddress: Address?
    private var tangemKeyFlow: TangemKeyFlow?
    private var tangemProvisioningCoordinator: TangemCardKeyProvisioningCoordinator?
    private var burnerProvisioningCoordinator: BurnerCardKeyProvisioningCoordinator?

    private var generateKeyFlow: GenerateKeyFlow?
    private var userProvisioningService: UserProvisioningService?
    private var cardsService: PrimaryCardService?
    private var hasCheckedRegisteredKeys = false
    init(sceneDelegate: SceneDelegate) {
        self.sceneDelegate = sceneDelegate
        isSignUp = AppSettings.isNewSignUp ?? false
        #if DEBUG
        LogService.shared.debug("[PostLoginGateCoordinator] isNewSignUp=\(isSignUp)")
        #endif
        // isNewSignUp is cleared in finish() once onboarding completes successfully,
        // so it survives app kills during onboarding.
    }

    func start(completion: @escaping () -> Void) {
        self.completion = completion
        evaluateAndProceed()
    }

    private func evaluateAndProceed() {
        guard App.shared.authRepository.isAuthenticated() else {
            finish()
            return
        }

        let leadManufacturer = Self.normalizedLeadManufacturer(AppSettings.leadCardManufacturer)
        let mobileKeyCount = KeyInfo.count(.deviceImported) + KeyInfo.count(.deviceGenerated)
        let localCardKeyCount = KeyInfo.count(.tangem) + KeyInfo.count(.tangem0) + KeyInfo.count(.burner)
        let hasNoVaults = Safe.countExcludingDemo == 0
        let requiredMobileKeyCount = leadManufacturer == "mobile" ? 2 : 1

        if !isSignUp && !hasCheckedRegisteredKeys {
            fetchRegisteredKeysAndProceed()
            return
        }

        let state = PostLoginGateState(
            hasSyncedVaults: hasAttemptedVaultSync,
            hasVaults: !hasNoVaults,
            mobileKeyCount: mobileKeyCount,
            requiredMobileKeyCount: requiredMobileKeyCount,
            hasCardKey: localCardKeyCount > 0,
            requiresCardKey: ["tangem", "burner"].contains(leadManufacturer),
            isSignUp: isSignUp,
            cardManufacturer: leadManufacturer
        )

        if shouldShowPostSignupInstructions(for: state) {
            showPostSignupInstructions()
            return
        }

        let nextAction = PostLoginGateEvaluator.nextAction(for: state)
        #if DEBUG
        LogService.shared.debug("[PostLoginGateCoordinator] Next action=\(String(describing: nextAction)) isSignUp=\(isSignUp)")
        #endif
        switch nextAction {
        case .startCardKeyFlow:
            startCardKeyFlow()
        case .syncVaults:
            ensureGateVisible()
            syncVaults()
        case .showPendingVaultActivation:
            ensureGateVisible()
            showPendingVaultActivation()
        case .startMobileKeyFlow:
            ensureGateVisible()
            startMobileKeyFlow()
        case .showContactRequired:
            showContactRequired()
        case .showMain:
            finish()
        }
    }

    private func shouldShowPostSignupInstructions(for state: PostLoginGateState) -> Bool {
        if AppSettings.didShowPostSignupInstructions && AppSettings.pendingPostSignupInstructions {
            AppSettings.pendingPostSignupInstructions = false
            return false
        }
        if isShowingPostSignupInstructions {
            return false
        }
        return AppSettings.pendingPostSignupInstructions && !AppSettings.didShowPostSignupInstructions && !state.hasCardKey
    }

    private func markPostSignupInstructionsShown() {
        AppSettings.didShowPostSignupInstructions = true
        AppSettings.pendingPostSignupInstructions = false
    }

    private func showPostSignupInstructions() {
        guard !isShowingPostSignupInstructions else { return }
        isShowingPostSignupInstructions = true

        let instructionsVC = CreateSafeInstructionsViewController()
        instructionsVC.onClose = { [weak self] in
            guard let self else { return }
            self.markPostSignupInstructionsShown()
            self.isShowingPostSignupInstructions = false
            self.ensureGateVisible()
            self.evaluateAndProceed()
        }
        instructionsVC.onPrimaryAction = { [weak self] in
            self?.markPostSignupInstructionsShown()
            self?.isShowingPostSignupInstructions = false
            self?.ensureGateVisible()
            self?.evaluateAndProceed()
        }

        let nav = UINavigationController(rootViewController: instructionsVC)
        sceneDelegate?.showPostLoginGateWindow(rootViewController: nav)
    }

    private func ensureGateVisible() {
        if gateViewController == nil {
            gateViewController = PostLoginGateViewController()
        }
        if let gateViewController {
            if let gateNavigationController {
                gateNavigationController.setViewControllers([gateViewController], animated: false)
            } else {
                gateNavigationController = UINavigationController(rootViewController: gateViewController)
            }

            if let gateNavigationController {
                sceneDelegate?.showPostLoginGateWindow(rootViewController: gateNavigationController)
            }
        }
    }

    private func syncVaults() {
        guard !isSyncingVaults else { return }
        isSyncingVaults = true
        gateViewController?.showLoading(message: "Cargando tus bóvedas")

        App.shared.vaultsRepository.syncVaultsFromBackend(force: true) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSyncingVaults = false
                self.hasAttemptedVaultSync = true

                switch result {
                case .success:
                    self.evaluateAndProceed()
                case .failure:
                    self.gateViewController?.showError(
                        message: "No hemos podido cargar tus bóvedas, por favor escribinos a hola@boveda.ai"
                    )
                }
            }
        }
    }

    private func showPendingVaultActivation() {
        gateViewController?.showPendingVaultActivation { [weak self] in
            guard let self else { return }
            self.hasAttemptedVaultSync = true
            self.evaluateAndProceed()
        }
    }

    private func fetchRegisteredKeysAndProceed() {
        let service = PrimaryCardService(
            authRepository: App.shared.authRepository,
            logger: LogService.shared
        )
        cardsService = service
        service.fetchHasRegisteredKeys { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.cardsService = nil
                switch result {
                case .success(let hasKeys):
                    if hasKeys {
                        #if DEBUG
                        LogService.shared.debug("[PostLoginGateCoordinator] Returning user has registered keys — skipping onboarding")
                        #endif
                        self.hasCheckedRegisteredKeys = true
                        self.evaluateAndProceed()
                    } else {
                        #if DEBUG
                        LogService.shared.debug("[PostLoginGateCoordinator] No registered keys found — starting onboarding as new signup")
                        #endif
                        self.convertToSignupMode()
                    }
                case .failure:
                    // Be conservative on errors: do not force key creation without certainty.
                    #if DEBUG
                    LogService.shared.debug("[PostLoginGateCoordinator] fetchHasRegisteredKeys error — treating as existing user")
                    #endif
                    self.hasCheckedRegisteredKeys = true
                    self.evaluateAndProceed()
                }
            }
        }
    }

    private func convertToSignupMode() {
        // Re-fetch the user record from the backend so we get the current cardManufacturer.
        let service = UserProvisioningService(
            authRepository: App.shared.authRepository,
            logger: LogService.shared
        )
        userProvisioningService = service
        service.ensureUserRecord { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.userProvisioningService = nil
                // Activate signup mode.
                self.isSignUp = true
                AppSettings.isNewSignUp = true
                AppSettings.pendingPostSignupInstructions = true
                AppSettings.didShowPostSignupInstructions = false
                #if DEBUG
                LogService.shared.debug("[PostLoginGateCoordinator] convertToSignupMode: cardManufacturer=\(AppSettings.leadCardManufacturer ?? "nil")")
                #endif
                self.evaluateAndProceed()
            }
        }
    }

    private func startMobileKeyFlow() {
        guard !isPresentingFlow else { return }
        guard let gateViewController else { return }
        if gateViewController.navigationController == nil {
            ensureGateVisible()
        }
        guard gateViewController.navigationController != nil else {
            return
        }

        isPresentingFlow = true
        let flow = GenerateKeyFlow { [weak self] success in
            guard let self else { return }
            self.generateKeyFlow = nil
            self.isPresentingFlow = false
            self.ensureGateVisible()
            self.evaluateAndProceed()
        }
        generateKeyFlow = flow
        gateViewController.push(flow: flow)
    }

    private func showContactRequired() {
        let msg = NSLocalizedString("auth_lead_pending_message", comment: "")
        let vc = ContactRequiredViewController(message: msg)
        let nav = UINavigationController(rootViewController: vc)
        sceneDelegate?.showPostLoginGateWindow(rootViewController: nav)
    }

    private func startCardKeyFlow() {
        guard !isProvisioningCardKey else { return }
        isProvisioningCardKey = true

        let manufacturer = Self.normalizedLeadManufacturer(AppSettings.leadCardManufacturer)

        if manufacturer.isEmpty {
            LogService.shared.info("[PostLoginGate][CardKey] Manufacturer missing; refreshing from backend...")
            ensureGateVisible()
            gateViewController?.showLoading(
                message: NSLocalizedString("post_login_card_key_loading", comment: "Card key loading message")
            )
            refreshLeadCardManufacturer { [weak self] in
                guard let self else { return }
                let refreshed = Self.normalizedLeadManufacturer(AppSettings.leadCardManufacturer)
                LogService.shared.info("[PostLoginGate][CardKey] Manufacturer(after refresh)=\(refreshed)")
                self.routeCardKeyFlow(manufacturer: refreshed)
            }
            return
        }

        LogService.shared.info("[PostLoginGate][CardKey] Manufacturer=\(manufacturer)")
        routeCardKeyFlow(manufacturer: manufacturer)
    }

    private func routeCardKeyFlow(manufacturer: String) {
        switch manufacturer {
        case "tangem":
            provisionTangemCardKey()
        case "burner":
            ensureGateVisible()
            provisionBurnerCardKey()
        default:
            isProvisioningCardKey = false
            showContactRequired()
        }
    }

    private func refreshLeadCardManufacturer(completion: @escaping () -> Void) {
        guard App.shared.authRepository.isAuthenticated() else {
            DispatchQueue.main.async { completion() }
            return
        }

        // IMPORTANT:
        // `UserProvisioningService` owns an `AuthenticatedHTTPClient` → `HTTPClient` → `URLSession`.
        // `HTTPClient.asyncExecute` uses `[weak self]` and `HTTPClient.deinit` cancels the session.
        // If we don't retain the service for the duration of the request, the completion may never fire
        // and we can get stuck on the loading screen forever.
        let service = UserProvisioningService(
            authRepository: App.shared.authRepository,
            logger: LogService.shared
        )
        userProvisioningService = service
        service.ensureUserRecord { _ in
            DispatchQueue.main.async {
                self.userProvisioningService = nil
                completion()
            }
        }
    }

    private static func normalizedLeadManufacturer(_ raw: String?) -> String {
        (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func provisionBurnerCardKey() {
        LogService.shared.info("[PostLoginGate][CardKey][Burner] Starting two-scan activation/import")

        lastCardKeyAddress = nil
        var activationNav: UINavigationController?

        let coordinator = BurnerCardKeyProvisioningCoordinator(
            targetSlot: 3,
            presentIntro: { [weak self] introVC in
                guard let self else { return }
                let nav = UINavigationController(rootViewController: introVC)
                activationNav = nav
                self.sceneDelegate?.showPostLoginGateWindow(rootViewController: nav)
            },
            presentPostActivationIntro: { [weak self] introVC in
                guard let self else { return }
                let nav = UINavigationController(rootViewController: introVC)
                activationNav = nav
                self.sceneDelegate?.showPostLoginGateWindow(rootViewController: nav)
            },
            onImportCompletion: { [weak self] success, address, cardId, cardPublicKey, walletPublicKey in
                guard let self else { return }
                self.isPresentingFlow = false
                self.burnerProvisioningCoordinator = nil
                if success, let address {
                    if let cardId {
                        self.registerPrimaryCardInBackend(cardId: cardId, manufacturer: "burner", cardPublicKey: cardPublicKey, walletPublicKey: walletPublicKey)
                    }
                    self.isProvisioningCardKey = false
                    self.showCardKeySuccess(address: address)
                } else {
                    self.showCardKeyError(messageKey: "post_login_card_key_import_failed")
                }
            },
            onActivationCancelled: { [weak self] in
                self?.isProvisioningCardKey = false
                self?.showContactRequired()
            }
        )

        burnerProvisioningCoordinator = coordinator
        coordinator.start()
    }

    private func provisionTangemCardKey() {
        LogService.shared.info("[PostLoginGate][CardKey][Tangem] Starting activation scan")

        lastCardKeyAddress = nil

        var activationNav: UINavigationController?
        let coordinator = TangemCardKeyProvisioningCoordinator(
            presentIntro: { [weak self] introVC in
                guard let self else { return }
                let nav = UINavigationController(rootViewController: introVC)
                activationNav = nav
                self.sceneDelegate?.showPostLoginGateWindow(rootViewController: nav)
            },
            presentActivation: { [weak self] activationVC in
                guard let self else { return }
                if let nav = activationNav {
                    nav.setViewControllers([activationVC], animated: false)
                    self.sceneDelegate?.showPostLoginGateWindow(rootViewController: nav)
                } else {
                    let nav = UINavigationController(rootViewController: activationVC)
                    self.sceneDelegate?.showPostLoginGateWindow(rootViewController: nav)
                }
            },
            presentPostActivationIntro: { [weak self] introVC in
                guard let self else { return }
                let nav = UINavigationController(rootViewController: introVC)
                activationNav = nav
                self.sceneDelegate?.showPostLoginGateWindow(rootViewController: nav)
            },
            presentImportFlow: { [weak self] flow in
                guard let self else { return }
                self.ensureGateVisible()
                self.isPresentingFlow = true
                self.tangemKeyFlow = flow
                self.gateViewController?.present(flow: flow, dismissableOnSwipe: false)
            },
            configureImportFlow: { [weak self] flow in
                flow.skipIntro = true
                flow.skipPostImportFlow = true
                flow.skipWalletSelection = true
                flow.onKeyImported = { [weak self] address in
                    self?.lastCardKeyAddress = address
                }
            },
            onImportCompletion: { [weak self] success in
                guard let self else { return }
                self.isPresentingFlow = false
                self.tangemKeyFlow = nil
                self.tangemProvisioningCoordinator = nil
                if success, let address = self.lastCardKeyAddress {
                    self.isProvisioningCardKey = false
                    self.showCardKeySuccess(address: address)
                } else {
                    self.showCardKeyError(messageKey: "post_login_card_key_import_failed")
                }
            },
            onActivationCancelled: { [weak self] in
                self?.isProvisioningCardKey = false
                self?.showContactRequired()
            }
        )
        tangemProvisioningCoordinator = coordinator
        coordinator.start()
    }

    private func registerPrimaryCardInBackend(cardId: String, manufacturer: String, cardPublicKey: Data? = nil, walletPublicKey: Data? = nil) {
        guard App.shared.authRepository.isAuthenticated() else { return }
        let cardPublicKeyHex = cardPublicKey.map { $0.map { String(format: "%02x", $0) }.joined() }
        let walletPublicKeyHex = walletPublicKey.map { $0.map { String(format: "%02x", $0) }.joined() }
        let payload = RegisterPrimaryCardPayload(
            manufacturer: manufacturer,
            cardId: cardId,
            firmwareLevel: nil,
            state: 1,
            cardPublicKey: cardPublicKeyHex,
            walletPublicKey: walletPublicKeyHex
        )
        let service = PrimaryCardRegistrationService(
            authRepository: App.shared.authRepository,
            logger: LogService.shared
        )
        service.registerPrimaryCard(payload: payload) { result in
            switch result {
            case .success:
                LogService.shared.info("[PostLoginGate][CardKey] Registered primary card (manufacturer=\(manufacturer), cardId=\(cardId))")
            case .failure(let error):
                LogService.shared.error("[PostLoginGate][CardKey] Failed to register primary card", error: error)
            }
        }
    }

    private func showCardKeySuccess(address: Address) {
        // Ensure backend registry is up-to-date (covers cases where the earlier best-effort
        // per-key registration was skipped or temporarily failed).
        OwnerKeyController.syncBackendKeyRegistry()

        let successVC = CardKeyActivatedViewController(address: address) { [weak self] in
            guard let self else { return }
            self.isPresentingFlow = false
            self.isProvisioningCardKey = false
            self.ensureGateVisible()
            self.evaluateAndProceed()
        }
        let nav = UINavigationController(rootViewController: successVC)
        sceneDelegate?.showPostLoginGateWindow(rootViewController: nav)
        isPresentingFlow = true
    }

    private func showCardKeyError(messageKey: String) {
        isProvisioningCardKey = false
        showContactRequired()
    }

    private func isUserCancelled(error: Error) -> Bool {
        if let tangemError = error as? TangemServiceError, case .userCancelled = tangemError {
            return true
        }
        if let burnerError = error as? BurnerService.BurnerServiceError, case .userCancelled = burnerError {
            return true
        }
        return false
    }

    private func finish() {
        AppSettings.isNewSignUp = false
        gateNavigationController = nil
        gateViewController = nil
        sceneDelegate?.dismissPostLoginGateWindow()
        completion?()
    }
}

extension PostLoginGateCoordinator {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        isPresentingFlow = false
        evaluateAndProceed()
    }
}

final class PostLoginGateViewController: ContainerViewController {
    private var loadingViewController: UIViewController?
    private var loadingMessage: String?
    private var errorViewController: UIViewController?
    private var pendingVaultActivationViewController: PendingVaultActivationViewController?
    private var introViewController: UIViewController?

    func showLoading(message: String) {
        if loadingViewController == nil || loadingMessage != message {
            loadingMessage = message
            loadingViewController = VaultSyncLoadingViewController(message: message)
        }
        viewControllers = [loadingViewController!]
        displayChild(at: 0, in: view)
    }

    func showError(message: String) {
        errorViewController = VaultSyncErrorViewController(message: message, showsSignOut: true)
        viewControllers = [errorViewController!]
        displayChild(at: 0, in: view)
    }

    func showError(message: String, onRetry: @escaping () -> Void) {
        errorViewController = PostLoginGateErrorViewController(
            message: message,
            retryTitle: NSLocalizedString("button_retry", comment: "Retry button title"),
            onRetry: onRetry
        )
        viewControllers = [errorViewController!]
        displayChild(at: 0, in: view)
    }

    func showIntro(title: String, detail: String) {
        introViewController = PostLoginGateIntroViewController(title: title, detail: detail)
        viewControllers = [introViewController!]
        displayChild(at: 0, in: view)
    }

    func showPendingVaultActivation(onRefresh: @escaping () -> Void) {
        if pendingVaultActivationViewController == nil {
            let vc = PendingVaultActivationViewController()
            vc.onVaultsRefreshed = onRefresh
            pendingVaultActivationViewController = vc
        } else {
            pendingVaultActivationViewController?.onVaultsRefreshed = onRefresh
        }
        viewControllers = [pendingVaultActivationViewController!]
        displayChild(at: 0, in: view)
    }
}
