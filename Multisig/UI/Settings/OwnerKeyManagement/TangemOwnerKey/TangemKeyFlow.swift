import UIKit

struct TangemWalletSelection {
    let cardId: String
    let walletPublicKey: Data
    let address: Address
    let derivationPath: String?
    let walletIndex: Int?
}

final class AddTangemKeyParameters: AddKeyParameters {
    let cardId: String
    let walletPublicKey: Data
    let derivationPath: String?
    let walletIndex: Int?

    init(address: Address,
         defaultName: String?,
         cardId: String,
         walletPublicKey: Data,
         derivationPath: String?,
         walletIndex: Int?) {
        self.cardId = cardId
        self.walletPublicKey = walletPublicKey
        self.derivationPath = derivationPath
        self.walletIndex = walletIndex
        super.init(address: address, name: defaultName, type: .tangem)
    }
}

final class TangemKeyFlowFactory: AddKeyFlowFactory {
    private let service: TangemService

    init(service: TangemService) {
        self.service = service
    }

    override func intro(completion: @escaping () -> Void) -> AddKeyOnboardingViewController {
        let introVC = super.intro(completion: completion)
        introVC.cards = [
            .init(image: UIImage(named: "ico-onboarding-key"),
                  title: "Tap your Tangem Card",
                  body: "Hold your Tangem card near the top of your iPhone and follow the on-screen instructions."),
            .init(image: UIImage(named: "ico-onboarding-key"),
                  title: "Choose the Wallet",
                  body: "Select which wallet on your Tangem card you would like to add as an owner."),
            .init(image: UIImage(named: "ico-onboarding-key"),
                  title: "Keep Control",
                  body: "Your private keys never leave the Tangem card. We only store metadata required to use the card for signing.")
        ]
        introVC.viewTrackingEvent = .tangemOwnerOnboarding
        introVC.navigationItem.title = "Connect Tangem Card"
        introVC.navigationItem.largeTitleDisplayMode = .never
        return introVC
    }

    func scan(onSelected: @escaping (TangemWalletSelection) -> Void,
              onCancel: @escaping () -> Void) -> TangemScanViewController {
        let controller = TangemScanViewController(service: service)
        controller.onWalletSelected = onSelected
        controller.onCancelled = onCancel
        return controller
    }

    func defaultName(cardId: String, walletIndex: Int?) -> String {
        let ordinal = KeyInfo.count(.tangem) + 1
        let suffix = cardId.suffix(4)
        if let walletIndex = walletIndex {
            return "Tangem \(ordinal) · \(suffix)#\(walletIndex)"
        }
        return "Tangem \(ordinal) · \(suffix)"
    }
}

final class TangemKeyFlow: AddKeyFlow {
    private let tangemService: TangemService

    private var tangemFactory: TangemKeyFlowFactory {
        factory as! TangemKeyFlowFactory
    }

    private var tangemParameters: AddTangemKeyParameters? {
        keyParameters as? AddTangemKeyParameters
    }

    init(service: TangemService = .shared, completion: @escaping (Bool) -> Void) {
        self.tangemService = service
        super.init(factory: TangemKeyFlowFactory(service: service), completion: completion)
    }

    override func didIntro() {
        showScan()
    }

    private func showScan() {
        let controller = tangemFactory.scan { [weak self] selection in
            self?.handle(selection: selection)
        } onCancel: { [weak self] in
            TangemLogger.info("Tangem key flow cancelled during scan")
            self?.stop(success: false)
        }

        show(controller)
    }

    private func handle(selection: TangemWalletSelection) {
        let defaultName = tangemFactory.defaultName(cardId: selection.cardId, walletIndex: selection.walletIndex)
        let parameters = AddTangemKeyParameters(address: selection.address,
                                                defaultName: defaultName,
                                                cardId: selection.cardId,
                                                walletPublicKey: selection.walletPublicKey,
                                                derivationPath: selection.derivationPath,
                                                walletIndex: selection.walletIndex)
        keyParameters = parameters
        TangemLogger.info("Prepared Tangem key import cardId=\(selection.cardId) walletIndex=\(selection.walletIndex ?? -1)")
        didGetKey()
    }

    override func doImport() -> Bool {
        guard let params = tangemParameters,
              let name = params.name else {
            assertionFailure("Missing Tangem key parameters")
            return false
        }

        let walletIndexStr = params.walletIndex.map { String($0) } ?? "nil"
        TangemLogger.info("Importing Tangem key cardId=\(params.cardId) walletIndex=\(walletIndexStr)")
        return OwnerKeyController.importKey(tangemCardId: params.cardId,
                                            walletPublicKey: params.walletPublicKey,
                                            address: params.address,
                                            name: name,
                                            derivationPath: params.derivationPath,
                                            walletIndex: params.walletIndex)
    }
}

