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
                  title: "Tap your Burner Card",
                  body: "Hold your Burner (HaLo) card near the top of your iPhone and follow the on-screen instructions."),
            .init(image: UIImage(named: "ico-hardware-wallet"),
                  title: "Choose a Slot",
                  body: "Each Burner card exposes multiple key slots. Pick the one you want to add as an owner."),
            .init(image: UIImage(named: "ico-hardware-wallet"),
                  title: "Secure By Design",
                  body: "Keys never leave the Burner card. We only store metadata required to use the card for signing.")
        ]
        introVC.viewTrackingEvent = .burnerOwnerOnboarding
        introVC.navigationItem.title = "Connect Burner Card"
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
        return "Burner \(ordinal) · \(suffix)#\(slot)"
    }
}

final class BurnerKeyFlow: AddKeyFlow {
    private let burnerService: BurnerService
    
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
    
    private func showScan() {
        let controller = burnerFactory.scan { [weak self] selection in
            self?.handle(selection: selection)
        } onCancel: { [weak self] in
            BurnerLogger.info("Burner key flow cancelled during scan")
            self?.stop(success: false)
        }
        
        show(controller)
    }
    
    private func handle(selection: BurnerKeySelection) {
        let defaultName = burnerFactory.defaultName(cardId: selection.cardId, slot: selection.slot)
        let parameters = AddBurnerKeyParameters(address: selection.address,
                                                defaultName: defaultName,
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

