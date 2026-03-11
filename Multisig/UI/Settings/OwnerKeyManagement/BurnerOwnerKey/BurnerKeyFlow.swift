//
//  BurnerKeyFlow.swift
//  Multisig
//
//  Created by GPT-5.1 Codex.
//

import UIKit
import SafeWeb3

struct BurnerKeySelection {
    let cardId: String
    let tagIdentifier: String
    let slot: Int
    let publicKey: Data
    let slot1PublicKey: Data?
    let address: Address
    let attestationValid: Bool
}

final class AddBurnerKeyParameters: AddKeyParameters {
    let cardId: String
    let tagIdentifier: String
    let slot: Int
    let walletPublicKey: Data
    let attestationValid: Bool
    let derivationPath: String?
    
    init(address: Address,
         defaultName: String?,
         cardId: String,
         tagIdentifier: String,
         slot: Int,
         walletPublicKey: Data,
         attestationValid: Bool,
         derivationPath: String? = nil) {
        self.cardId = cardId
        self.tagIdentifier = tagIdentifier
        self.slot = slot
        self.walletPublicKey = walletPublicKey
        self.attestationValid = attestationValid
        self.derivationPath = derivationPath
        super.init(address: address, name: defaultName, type: .burner)
    }
}

final class BurnerKeyFlowFactory: AddKeyFlowFactory {
    private let service: BurnerService
    
    init(service: BurnerService) {
        self.service = service
    }
    
    override func intro(completion: @escaping () -> Void) -> AddKeyOnboardingViewController {
        let introVC = super.intro(completion: completion)
        introVC.cards = [
            .init(
                image: UIImage(named: "ico-nfc"),
                title: NSLocalizedString("ui_tangem_card_key_tap_title", comment: "Title for tapping the Tangem Card Key"),
                body: NSLocalizedString("ui_tangem_card_key_intro_body", comment: "Intro body for Tangem card key activation")
            ),
            .init(
                image: UIImage(named: "ico-lock"),
                title: NSLocalizedString("ui_tangem_card_key_secure_title", comment: "Security title for Tangem card key activation"),
                body: NSLocalizedString("ui_tangem_card_key_secure_body", comment: "Security body for Tangem card key activation")
            )
        ]
        introVC.viewTrackingEvent = .burnerOwnerOnboarding
        introVC.navigationItem.title = NSLocalizedString("ui_tangem_activate_card_key_title", comment: "Title for the Tangem card key activation flow")
        introVC.navigationItem.largeTitleDisplayMode = .never
        return introVC
    }
    
    func scan(onSelected: @escaping (BurnerKeySelection) -> Void,
              onCancel: @escaping () -> Void) -> BurnerScanViewController {
        let controller = BurnerScanViewController(service: service)
        controller.onSlotSelected = onSelected
        controller.onCancelled = onCancel
        return controller
    }
    
    func defaultName(cardId: String, slot: Int) -> String {
        let ordinal = KeyInfo.count(.burner) + 1
        let suffix = cardId.suffix(4)
        return String(
            format: NSLocalizedString("ui_burner_default_name_format", comment: "Default name format for Burner keys, e.g. 'Burner 1 · 1234#1'"),
            ordinal,
            String(suffix),
            slot
        )
    }
}

final class BurnerKeyFlow: AddKeyFlow {
    private let burnerService: BurnerService
    private let defaultKeyName = "Card Key"
    var onKeyImported: ((Address) -> Void)?
    var skipIntro: Bool = false
    var skipPostImportFlow: Bool = false
    var targetSlot: Int? = 3
    
    private var burnerFactory: BurnerKeyFlowFactory {
        factory as! BurnerKeyFlowFactory
    }
    
    private var burnerParameters: AddBurnerKeyParameters? {
        keyParameters as? AddBurnerKeyParameters
    }
    
    init(service: BurnerService = .shared, completion: @escaping (Bool) -> Void) {
        self.burnerService = service
        super.init(factory: BurnerKeyFlowFactory(service: service), completion: completion)
    }

    override func start() {
        if skipIntro {
            didIntro()
        } else {
            super.start()
        }
    }
    
    override func didIntro() {
        showScan()
    }

    override func didGetKey() {
        // Skip the "Enter Key Name" screen for Burner cards.
        keyParameters.name = defaultKeyName
        importKey()
    }

    override func didImport() {
        if skipPostImportFlow {
            stop(success: true)
        } else {
            super.didImport()
        }
    }
    
    private func showScan() {
        let controller = burnerFactory.scan { [weak self] selection in
            self?.handle(selection: selection)
        } onCancel: { [weak self] in
            BurnerLogger.info("Burner key flow cancelled during scan")
            self?.stop(success: false)
        }
        
        // For card-key provisioning we auto-select the target slot (default: 3).
        controller.autoSelectFirstSlot = true
        controller.targetSlot = targetSlot
        
        show(controller)
    }
    
    private func handle(selection: BurnerKeySelection) {
        registerPrimaryCardInBackend(
            cardId: selection.cardId,
            cardPublicKey: selection.slot1PublicKey,
            walletPublicKey: selection.publicKey
        )
        let parameters = AddBurnerKeyParameters(address: selection.address,
                                                defaultName: defaultKeyName,
                                                cardId: selection.cardId,
                                                tagIdentifier: selection.tagIdentifier,
                                                slot: selection.slot,
                                                walletPublicKey: selection.publicKey,
                                                attestationValid: selection.attestationValid,
                                                derivationPath: nil)
        keyParameters = parameters
        BurnerLogger.info("Prepared Burner key import cardId=\(selection.cardId) slot=\(selection.slot)")
        didGetKey()
    }

    private func registerPrimaryCardInBackend(cardId: String, cardPublicKey: Data?, walletPublicKey: Data?) {
        guard App.shared.authRepository.isAuthenticated() else {
            BurnerLogger.debug("Burner key flow: Skipping primary card registration (user not authenticated)")
            return
        }

        let cardPublicKeyHex = cardPublicKey.map { $0.map { String(format: "%02x", $0) }.joined() }
        let walletPublicKeyHex = walletPublicKey.map { $0.map { String(format: "%02x", $0) }.joined() }

        let payload = RegisterPrimaryCardPayload(
            manufacturer: "burner",
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
                BurnerLogger.info("Burner key flow: Registered primary Burner card (cardId=\(cardId))")
            case .failure(let error):
                BurnerLogger.error("Burner key flow: Failed to register primary Burner card", error: error)
            }
        }
    }
    
    override func keyAdded() {
        stop(success: true)
    }

    override func doImport() -> Bool {
        guard let params = burnerParameters,
              let name = params.name else {
            assertionFailure("Missing Burner key parameters")
            return false
        }
        
        let imported = OwnerKeyController.importKey(burnerCardId: params.cardId,
                                                    tagIdentifier: params.tagIdentifier,
                                                    slot: params.slot,
                                                    walletPublicKey: params.walletPublicKey,
                                                    address: params.address,
                                                    name: name,
                                                    derivationPath: params.derivationPath,
                                                    attestationValid: params.attestationValid)
        if imported {
            onKeyImported?(params.address)
        }
        return imported
    }
}

final class BurnerCardKeyProvisioningCoordinator {
    typealias PresentIntro = (UIViewController) -> Void
    typealias PresentPostActivationIntro = (UIViewController) -> Void
    typealias ImportCompletion = (Bool, Address?, String?, Data?, Data?) -> Void

    private let service: BurnerService
    private let targetSlot: Int
    private let presentIntro: PresentIntro
    private let presentPostActivationIntro: PresentPostActivationIntro
    private let onImportCompletion: ImportCompletion
    private let onActivationCancelled: (() -> Void)?
    private let importStartDelay: TimeInterval

    private var pendingImport = false

    init(service: BurnerService = .shared,
         targetSlot: Int = 3,
         presentIntro: @escaping PresentIntro,
         presentPostActivationIntro: @escaping PresentPostActivationIntro,
         onImportCompletion: @escaping ImportCompletion,
         onActivationCancelled: (() -> Void)? = nil,
         importStartDelay: TimeInterval = 0.6) {
        self.service = service
        self.targetSlot = targetSlot
        self.presentIntro = presentIntro
        self.presentPostActivationIntro = presentPostActivationIntro
        self.onImportCompletion = onImportCompletion
        self.onActivationCancelled = onActivationCancelled
        self.importStartDelay = importStartDelay
    }

    func start() {
        BurnerLogger.info("[BurnerProvisioning] Starting card key provisioning flow")
        let introVC = buildIntroViewController { [weak self] in
            self?.startActivationScan()
        }
        presentIntro(introVC)
    }

    private func buildIntroViewController(onNext: @escaping () -> Void) -> AddKeyOnboardingViewController {
        let introVC = AddKeyOnboardingViewController()
        introVC.cards = [
            .init(
                image: UIImage(named: "ico-nfc"),
                title: NSLocalizedString("ui_tangem_card_key_tap_title", comment: "Title for tapping card key now"),
                body: NSLocalizedString("ui_tangem_card_key_intro_body", comment: "Intro body for card key activation")
            ),
            .init(
                image: UIImage(named: "ico-lock"),
                title: NSLocalizedString("ui_tangem_card_key_secure_title", comment: "Security title for Tangem card key activation"),
                body: NSLocalizedString("ui_tangem_card_key_secure_body", comment: "Security body for Tangem card key activation")
            )
        ]
        introVC.viewTrackingEvent = .burnerOwnerOnboarding
        introVC.navigationItem.title = NSLocalizedString("ui_tangem_activate_card_key_title", comment: "Title for the Tangem card key activation flow")
        introVC.navigationItem.largeTitleDisplayMode = .never
        introVC.completion = onNext
        return introVC
    }

    private func buildPostActivationIntroViewController(onNext: @escaping () -> Void) -> AddKeyOnboardingViewController {
        let introVC = AddKeyOnboardingViewController()
        introVC.cards = [
            .init(
                image: UIImage(named: "ico-nfc"),
                title: "",
                body: NSLocalizedString("ui_tangem_card_key_second_scan_body", comment: "Second scan instructions after card key activation")
            )
        ]
        introVC.viewTrackingEvent = .burnerOwnerOnboarding
        introVC.navigationItem.title = NSLocalizedString("ui_tangem_activate_card_key_title", comment: "Title for the Tangem card key activation flow")
        introVC.navigationItem.largeTitleDisplayMode = .never
        introVC.completion = onNext
        return introVC
    }

    private func startActivationScan() {
        BurnerLogger.info("[BurnerProvisioning] Starting activation scan (gen_key slot=\(targetSlot))")

        Task { [weak self] in
            guard let self else { return }
            do {
                let generated = try await self.service.generateKeyIfNeeded(
                    slot: self.targetSlot,
                    alertMessage: NSLocalizedString("ui_tangem_scan_message_body", comment: "Tangem scan message body")
                )
                if generated != nil {
                    BurnerLogger.info("[BurnerProvisioning] Activation completed for slot \(self.targetSlot)")
                } else {
                    BurnerLogger.info("[BurnerProvisioning] Slot \(self.targetSlot) already initialized; proceeding to second scan")
                }
                self.pendingImport = true
            } catch {
                if self.isUserCancelled(error: error) {
                    BurnerLogger.info("[BurnerProvisioning] Activation cancelled by user")
                    self.pendingImport = false
                } else {
                    BurnerLogger.warning("[BurnerProvisioning] Activation scan failed; proceeding silently to second scan. error=\(error.localizedDescription)")
                    self.pendingImport = true
                }
            }

            await MainActor.run {
                self.handleActivationFinished()
            }
        }
    }

    private func handleActivationFinished() {
        guard pendingImport else {
            onActivationCancelled?()
            return
        }

        let introVC = buildPostActivationIntroViewController { [weak self] in
            self?.startImportFlow()
        }
        presentPostActivationIntro(introVC)
    }

    private func startImportFlow() {
        BurnerLogger.info("[BurnerProvisioning] Starting second scan step for key import")
        DispatchQueue.main.asyncAfter(deadline: .now() + importStartDelay) { [weak self] in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                do {
                    let summary = try await self.service.scanCard(
                        forceRefresh: true,
                        alertMessage: NSLocalizedString("ui_tangem_scan_message_body", comment: "Tangem scan message body")
                    )
                    guard let slot = summary.keySlots.first(where: { $0.slot == self.targetSlot }) else {
                        BurnerLogger.error("[BurnerProvisioning] Slot \(self.targetSlot) not found during second scan")
                        await MainActor.run {
                            self.onImportCompletion(false, nil, nil, nil, nil)
                        }
                        return
                    }

                    let imported = OwnerKeyController.importKey(
                        burnerCardId: summary.cardId,
                        tagIdentifier: summary.tagIdentifier,
                        slot: slot.slot,
                        walletPublicKey: slot.publicKey,
                        address: slot.ethereumAddress,
                        name: NSLocalizedString("ui_card_key_default_name", comment: "Default card key name"),
                        derivationPath: nil,
                        attestationValid: slot.attestationValid
                    )

                    let slot1PublicKey = summary.keySlots.first(where: { $0.slot == 1 })?.publicKey
                    let walletPublicKey = slot.publicKey

                    await MainActor.run {
                        BurnerLogger.info("[BurnerProvisioning] Key import completed. success=\(imported)")
                        self.onImportCompletion(imported, imported ? slot.ethereumAddress : nil, imported ? summary.cardId : nil, slot1PublicKey, imported ? walletPublicKey : nil)
                    }
                } catch {
                    BurnerLogger.error("[BurnerProvisioning] Second scan/import failed", error: error)
                    await MainActor.run {
                        self.onImportCompletion(false, nil, nil, nil, nil)
                    }
                }
            }
        }
    }

    private func isUserCancelled(error: Error) -> Bool {
        if let burnerError = error as? BurnerService.BurnerServiceError,
           case .userCancelled = burnerError {
            return true
        }
        return false
    }
}

