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
         walletIndex: Int?,
         keyType: KeyType = .tangem) {
        self.cardId = cardId
        self.walletPublicKey = walletPublicKey
        self.derivationPath = derivationPath
        self.walletIndex = walletIndex
        super.init(address: address, name: defaultName, type: keyType)
    }
}

final class TangemKeyFlowFactory: AddKeyFlowFactory {
    private let service: TangemCardService
    private let keyType: KeyType

    init(service: TangemCardService, keyType: KeyType = .tangem) {
        self.service = service
        self.keyType = keyType
    }

    override func intro(completion: @escaping () -> Void) -> AddKeyOnboardingViewController {
        let introVC = super.intro(completion: completion)
        introVC.cards = [
            .init(image: UIImage(named: "ico-nfc"),
                  title: "",
                  body: NSLocalizedString("ui_tangem_card_key_intro_body", comment: "Intro body for Tangem card key activation")),
            .init(image: UIImage(named: "ico-lock"),
                  title: NSLocalizedString("ui_tangem_card_key_secure_title", comment: "Security title for Tangem card key activation"),
                  body: NSLocalizedString("ui_tangem_card_key_secure_body", comment: "Security body for Tangem card key activation"))
        ]
        introVC.viewTrackingEvent = .tangemOwnerOnboarding
        introVC.navigationItem.title = NSLocalizedString("ui_tangem_activate_card_key_title", comment: "Title for the Tangem card key activation flow")
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
        return "Card Key"
    }
}

final class TangemKeyFlow: AddKeyFlow {
    private let tangemService: TangemCardService
    private let keyType: KeyType
    private var prefilledSelection: TangemWalletSelection?
    private let defaultKeyName = "Card Key"
    var onKeyImported: ((Address) -> Void)?
    var onWalletSelected: ((TangemWalletSelection) -> Void)?
    var skipIntro: Bool = false
    var skipPostImportFlow: Bool = false
    var skipWalletSelection: Bool = false

    private var tangemFactory: TangemKeyFlowFactory {
        factory as! TangemKeyFlowFactory
    }

    private var tangemParameters: AddTangemKeyParameters? {
        keyParameters as? AddTangemKeyParameters
    }

    init(service: TangemCardService = TangemService.shared, keyType: KeyType = .tangem, completion: @escaping (Bool) -> Void) {
        self.tangemService = service
        self.keyType = keyType
        super.init(factory: TangemKeyFlowFactory(service: service, keyType: keyType), completion: completion)
    }

    /// Starts a Tangem import flow using an already-activated card wallet.
    /// The intro screen will be shown, but the scan step will be skipped.
    convenience init(activatedCardInfo: ActivatedCardInfo,
                     service: TangemCardService = TangemService.shared,
                     keyType: KeyType = .tangem,
                     completion: @escaping (Bool) -> Void) {
        self.init(service: service, keyType: keyType, completion: completion)
        self.prefilledSelection = TangemWalletSelection(
            cardId: activatedCardInfo.cardId,
            walletPublicKey: activatedCardInfo.wallet.publicKey,
            address: activatedCardInfo.ethereumAddress,
            derivationPath: nil,
            walletIndex: activatedCardInfo.wallet.index
        )
    }

    override func start() {
        if skipIntro {
            didIntro()
        } else {
            // Always show the intro screen, even when we have prefilled selection from activation
            super.start()
        }
    }

    override func didIntro() {
        // If we have a prefilled selection from activation, use it instead of scanning
        if let selection = prefilledSelection {
            prefilledSelection = nil
            handle(selection: selection)
        } else {
            showScan()
        }
    }

    override func didGetKey() {
        // Skip the "Enter Key Name" screen for Tangem cards.
        // Always use a consistent local name.
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
        let controller = tangemFactory.scan { [weak self] selection in
            self?.handle(selection: selection)
        } onCancel: { [weak self] in
            TangemLogger.info("Tangem key flow cancelled during scan")
            self?.stop(success: false)
        }
        controller.autoSelectFirstWallet = skipWalletSelection

        show(controller)
    }

    private func handle(selection: TangemWalletSelection) {
        onWalletSelected?(selection)
        let defaultName = tangemFactory.defaultName(cardId: selection.cardId, walletIndex: selection.walletIndex)
        let parameters = AddTangemKeyParameters(address: selection.address,
                                                defaultName: defaultName,
                                                cardId: selection.cardId,
                                                walletPublicKey: selection.walletPublicKey,
                                                derivationPath: selection.derivationPath,
                                                walletIndex: selection.walletIndex,
                                                keyType: keyType)
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
        let imported: Bool
        switch keyType {
        case .tangem:
            imported = OwnerKeyController.importKey(tangemCardId: params.cardId,
                                                    walletPublicKey: params.walletPublicKey,
                                                    address: params.address,
                                                    name: name,
                                                    derivationPath: params.derivationPath,
                                                    walletIndex: params.walletIndex)
        case .tangem0:
            imported = OwnerKeyController.importKey(tangem0CardId: params.cardId,
                                                    walletPublicKey: params.walletPublicKey,
                                                    address: params.address,
                                                    name: name,
                                                    derivationPath: params.derivationPath,
                                                    walletIndex: params.walletIndex)
        default:
            assertionFailure("Unsupported Tangem key type \(keyType)")
            imported = false
        }
        if imported {
            onKeyImported?(params.address)
        }
        return imported
    }
}

