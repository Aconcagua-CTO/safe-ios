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
            .init(image: UIImage(named: "ico-hardware-wallet"),
                  title: NSLocalizedString("ui_burner_onboarding_tap_title", comment: "Burner onboarding card title"),
                  body: NSLocalizedString("ui_burner_onboarding_tap_body", comment: "Burner onboarding card body")),
            .init(image: UIImage(named: "ico-hardware-wallet"),
                  title: NSLocalizedString("ui_burner_onboarding_pick_slot_title", comment: "Burner onboarding card title"),
                  body: NSLocalizedString("ui_burner_onboarding_pick_slot_body", comment: "Burner onboarding card body")),
            .init(image: UIImage(named: "ico-hardware-wallet"),
                  title: NSLocalizedString("ui_burner_onboarding_secure_title", comment: "Burner onboarding card title"),
                  body: NSLocalizedString("ui_burner_onboarding_secure_body", comment: "Burner onboarding card body"))
        ]
        introVC.viewTrackingEvent = .burnerOwnerOnboarding
        introVC.navigationItem.title = NSLocalizedString("ui_burner_connect_card_title", comment: "Title for the burner owner key connect flow")
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
    
    override func didIntro() {
        showScan()
    }

    override func didGetKey() {
        // Skip the "Enter Key Name" screen for Burner cards.
        keyParameters.name = defaultKeyName
        importKey()
    }
    
    private func showScan() {
        let controller = burnerFactory.scan { [weak self] selection in
            self?.handle(selection: selection)
        } onCancel: { [weak self] in
            BurnerLogger.info("Burner key flow cancelled during scan")
            self?.stop(success: false)
        }
        
        // Always pick the first slot (no user selection).
        controller.autoSelectFirstSlot = true
        
        show(controller)
    }
    
    private func handle(selection: BurnerKeySelection) {
        registerPrimaryCardInBackend(cardId: selection.cardId)
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

    private func registerPrimaryCardInBackend(cardId: String) {
        guard App.shared.authRepository.isAuthenticated() else {
            BurnerLogger.debug("Burner key flow: Skipping primary card registration (user not authenticated)")
            return
        }

        let payload = RegisterPrimaryCardPayload(
            manufacturer: "burner",
            cardId: cardId,
            firmwareLevel: nil,
            state: 1
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
        
        return OwnerKeyController.importKey(burnerCardId: params.cardId,
                                            tagIdentifier: params.tagIdentifier,
                                            slot: params.slot,
                                            walletPublicKey: params.walletPublicKey,
                                            address: params.address,
                                            name: name,
                                            derivationPath: params.derivationPath,
                                            attestationValid: params.attestationValid)
    }
}

