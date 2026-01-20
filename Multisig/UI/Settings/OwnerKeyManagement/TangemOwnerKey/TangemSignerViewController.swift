import UIKit
import SafeWeb3
import TangemSdk

final class TangemSignerViewController: UINavigationController {
    var completion: ((String) -> Void)?
    var txCompletion: (((v: UInt8, r: Data, s: Data)) -> Void)?
    var onClose: (() -> Void)?

    private let request: SignRequest
    private let tangemService: TangemSigningService

    init(request: SignRequest, service: TangemSigningService = TangemService.shared) {
        self.request = request
        self.tangemService = service
        let contentVC = TangemSignContentViewController(request: request, service: service)
        super.init(rootViewController: contentVC)
        configure(with: contentVC)
        modalPresentationStyle = .formSheet
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure(with contentVC: TangemSignContentViewController) {
        contentVC.onSignedHash = { [weak self] signature in
            guard let self else { return }
            self.completion?(signature)
            self.dismiss(animated: true)
        }

        contentVC.onSignedTransaction = { [weak self] signature in
            guard let self else { return }
            self.txCompletion?(signature)
            self.dismiss(animated: true)
        }

        contentVC.onClose = { [weak self] in
            guard let self else { return }
            self.onClose?()
            self.dismiss(animated: true)
        }
    }
}

private enum TangemSignerError: LocalizedError {
    case missingMetadata
    case walletNotFound
    case invalidHashLength
    case invalidSignature
    case signerMismatch

    var errorDescription: String? {
        switch self {
        case .missingMetadata:
            return "Tangem card metadata is missing. Please re-import the card."
        case .walletNotFound:
            return "The selected Tangem card does not contain the expected wallet."
        case .invalidHashLength:
            return "Expected a 32-byte hash to sign."
        case .invalidSignature:
            return "Tangem returned an invalid signature."
        case .signerMismatch:
            return "The Tangem card signed with a different address than expected."
        }
    }
}

private final class TangemSignContentViewController: UIViewController {
    var onSignedHash: ((String) -> Void)?
    var onSignedTransaction: (((v: UInt8, r: Data, s: Data)) -> Void)?
    var onClose: (() -> Void)?

    private enum State {
        case idle
        case verifyingCard
        case waitingForSignature
        case signing
        case error(String)
    }

    private struct SigningPayload {
        enum Kind {
            case hash
            case transaction(chainId: Int, isLegacy: Bool)
        }

        let hash: Data
        let kind: Kind
    }

    private let request: SignRequest
    private let service: TangemSigningService

    private let statusLabel = UILabel()
    private let detailLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let actionButton = UIButton(type: .system)
    private let stackView = UIStackView()

    private var state: State = .idle {
        didSet { updateUI(for: state) }
    }

    private var signingTask: Task<Void, Never>?
    private var hasStarted = false

    init(request: SignRequest, service: TangemSigningService) {
        self.request = request
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        signingTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .backgroundSecondary
        navigationItem.title = request.title
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel,
                                                            target: self,
                                                            action: #selector(cancelTapped))

        configureStackView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasStarted else { return }
        hasStarted = true
        startSigning()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        signingTask?.cancel()
    }

    private func configureStackView() {
        statusLabel.font = UIFont.preferredFont(forTextStyle: .title2)
        statusLabel.textColor = .labelPrimary
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center

        detailLabel.font = UIFont.preferredFont(forTextStyle: .body)
        detailLabel.textColor = .labelSecondary
        detailLabel.numberOfLines = 0
        detailLabel.textAlignment = .center

        activityIndicator.hidesWhenStopped = true

        actionButton.setTitle("Try Again", for: .normal)
        actionButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        actionButton.isHidden = true

        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(statusLabel)
        stackView.addArrangedSubview(detailLabel)
        stackView.addArrangedSubview(activityIndicator)
        stackView.addArrangedSubview(actionButton)

        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }

    private func startSigning() {
        signingTask?.cancel()
        state = .waitingForSignature
        TangemLogger.debug("TangemSigner ▶️ Starting signing flow for request: signerAddress=\(request.signer.address.checksummed)")

        signingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let metadata = try self.metadata()
                let walletIndexLog = metadata.walletIndex.map { String($0) } ?? "nil"
                let derivationPathLog = metadata.derivationPath ?? "nil"
                TangemLogger.debug("TangemSigner ▶️ Metadata: cardId=\(metadata.cardId), walletIndex=\(walletIndexLog), derivationPath=\(derivationPathLog)")
                TangemLogger.debug("TangemSigner ▶️ Metadata wallet public key (\(metadata.walletPublicKey.count) bytes) = \(metadata.walletPublicKey.tangemHexDescription())")
                
                let normalizedPublicKey = try self.service.normalizedWalletPublicKey(metadata.walletPublicKey)
                TangemLogger.debug("TangemSigner ▶️ Normalized wallet public key (\(normalizedPublicKey.count) bytes) = \(normalizedPublicKey.tangemHexDescription())")
                
                let payload = try self.makeSigningPayload()
                let payloadDescription: String = {
                    switch payload.kind {
                    case .hash:
                        return "hash"
                    case .transaction(let chainId, let isLegacy):
                        return "transaction(chainId:\(chainId), isLegacy:\(isLegacy))"
                    }
                }()
                TangemLogger.debug("TangemSigner ▶️ Signing payload: kind=\(payloadDescription), hash=\(payload.hash.tangemHexDescription())")

                let signingMessage = Message(
                    header: "Safe Wallet",
                    body: "Hold your Tangem card near the top of your iPhone to sign."
                )
                
                TangemLogger.debug("TangemSigner ▶️ Invoking signing service \(String(describing: type(of: self.service)))")
                let result = try await self.service.signHash(cardId: metadata.cardId,
                                                             walletPublicKey: metadata.walletPublicKey,
                                                             hash: payload.hash,
                                                             derivationPath: metadata.derivationPath,
                                                             walletIndex: metadata.walletIndex,
                                                             initialMessage: signingMessage)
                TangemLogger.debug("TangemSigner ▶️ Tangem service returned signature (\(result.signature.count) bytes) totalSigned=\(result.totalSignedHashes ?? -1)")
                TangemLogger.debug("TangemSigner ▶️ Raw signature = \(result.signature.tangemHexDescription())")
                TangemLogger.debug("TangemSigner ▶️ Terminal linked status: \(result.linkedTerminalStatus?.rawValue ?? "unknown")")

                await MainActor.run {
                    self.state = .signing
                }

                let processed = try self.processSignature(result: result,
                                                           hash: payload.hash,
                                                           normalizedPublicKey: normalizedPublicKey,
                                                           expectedAddress: self.request.signer.address)

                await MainActor.run {
                    switch (payload.kind, processed) {
                    case (.hash, let .hash(signature)):
                        TangemLogger.info("Tangem signing completed for card \(metadata.cardId) (hash)")
                        self.onSignedHash?(signature)
                    case (.transaction, let .transaction(signature)):
                        TangemLogger.info("Tangem signing completed for card \(metadata.cardId) (transaction)")
                        self.onSignedTransaction?(signature)
                    default:
                        TangemLogger.error("Tangem signing payload mismatch")
                        self.state = .error(TangemSignerError.invalidSignature.errorDescription ?? "Invalid signature")
                    }
                }

            } catch {
                guard !Task.isCancelled else { return }
                TangemLogger.error("Tangem signing failed", error: error)
                let message = self.message(for: error)
                await MainActor.run {
                    self.state = .error(message)
                }
            }
        }
    }

    private func metadata() throws -> KeyInfo.TangemKeyMetadata {
        guard let data = request.signer.metadata else {
            throw TangemSignerError.missingMetadata
        }

        if request.signer.keyType == .tangem0 {
            guard let metadata = KeyInfo.Tangem0KeyMetadata.from(data: data) else {
                throw TangemSignerError.missingMetadata
            }
            return KeyInfo.TangemKeyMetadata(
                cardId: metadata.cardId,
                walletPublicKey: metadata.walletPublicKey,
                derivationPath: metadata.derivationPath,
                walletIndex: metadata.walletIndex
            )
        }

        guard let metadata = KeyInfo.TangemKeyMetadata.from(data: data) else {
            throw TangemSignerError.missingMetadata
        }
        return metadata
    }

    private func makeSigningPayload() throws -> SigningPayload {
        switch request.payload {
        case .hash(let hex):
            let data = Foundation.Data(hexWC: hex)
            if data.count == 32 {
                return SigningPayload(hash: data, kind: .hash)
            }

            // Treat as personal_sign payload
            let prefix = "\u{19}Ethereum Signed Message:\n\(data.count)".data(using: .utf8) ?? Foundation.Data()
            let prefixed = prefix + data
            let hash = EthHasher.hash(prefixed)
            return SigningPayload(hash: hash, kind: .hash)

        case .rawTx(let data, let chainId, let isLegacy):
            let hash = EthHasher.hash(data)
            return SigningPayload(hash: hash, kind: .transaction(chainId: chainId, isLegacy: isLegacy))
        }
    }

    private enum ProcessedSignature {
        case hash(String)
        case transaction((v: UInt8, r: Data, s: Data))
    }

    private func processSignature(result: TangemSignResult,
                                  hash: Data,
                                  normalizedPublicKey: Data,
                                  expectedAddress: Address) throws -> ProcessedSignature {
        guard result.signature.count == 64 else {
            throw TangemSignerError.invalidSignature
        }

        TangemLogger.debug("TangemSigner ▶️ Processing signature. Expected address=\(expectedAddress.checksummed)")
        TangemLogger.debug("TangemSigner ▶️ Hash (\(hash.count) bytes) = \(hash.tangemHexDescription())")
        TangemLogger.debug("TangemSigner ▶️ Normalized public key (\(normalizedPublicKey.count) bytes) = \(normalizedPublicKey.tangemHexDescription())")

        let ownerAddress = try service.ethereumAddress(fromNormalizedPublicKey: normalizedPublicKey)
        guard ownerAddress == expectedAddress else {
            TangemLogger.error("TangemSigner ❌ Signer mismatch. Derived address=\(ownerAddress.checksummed) expected=\(expectedAddress.checksummed)")
            throw TangemSignerError.signerMismatch
        }
        TangemLogger.debug("TangemSigner ▶️ Derived signer address matches expected address (\(ownerAddress.checksummed))")

        // Tangem signature is r (32 bytes) + s (32 bytes)
        let rSlice = result.signature.prefix(32)
        let sSlice = result.signature.suffix(32)
        let rData = Foundation.Data(Array(rSlice))
        let sData = Foundation.Data(Array(sSlice))
        TangemLogger.debug("TangemSigner ▶️ Signature components: r=\(rData.tangemHexDescription()), s=\(sData.tangemHexDescription())")

        // Recover the correct v by testing both possible values (0 and 1)
        let recoveryId = try findRecoveryId(r: rData,
                                            s: sData,
                                            hash: hash,
                                            expectedAddress: ownerAddress)
        TangemLogger.debug("TangemSigner ▶️ Recovery ID selected: \(recoveryId)")

        // For Safe transactions: v should be 27 or 28
        let vForSafe = UInt8(27 + recoveryId)
        TangemLogger.debug("TangemSigner ▶️ Computed Safe-compatible v=\(vForSafe)")

        // Construct full signature for hex format: r + s + v
        var signatureData = Foundation.Data()
        signatureData.append(rData)
        signatureData.append(sData)
        signatureData.append(vForSafe)

        let signatureHex = signatureData.toHexStringWithPrefix()
        TangemLogger.debug("TangemSigner ▶️ Final signature payload = \(signatureHex)")

        switch request.payload {
        case .hash:
            return .hash(signatureHex)
        case .rawTx:
            // For transaction signing, return v as parity (0 or 1)
            return .transaction((v: UInt8(recoveryId), r: rData, s: sData))
        }
    }

    private func findRecoveryId(r: Data, s: Data, hash: Data, expectedAddress: Address) throws -> Int {
        let rBytes = Array(r)
        let sBytes = Array(s)

        // Try both compressed and uncompressed recovery since Tangem cards may sign with either format
        for recoveryId in 0...1 {
            let v = UInt8(27 + recoveryId)
            TangemLogger.debug("TangemSigner ▶️ Attempting recoveryId=\(recoveryId) using SECP256K1")
            guard let signature = SECP256K1.marshalSignature(v: v, r: rBytes, s: sBytes) else {
                TangemLogger.warning("TangemSigner ⚠️ marshalSignature failed for recoveryId=\(recoveryId)")
                continue
            }

            // Try both compressed and uncompressed key recovery
            for compressed in [false, true] {
                if let recoveredKey = SECP256K1.recoverPublicKey(hash: hash, signature: signature, compressed: compressed) {
                    do {
                        TangemLogger.debug("TangemSigner ▶️ SECP256K1 recoveryId=\(recoveryId) compressed=\(compressed) recovered key (\(recoveredKey.count) bytes) = \(recoveredKey.tangemHexDescription())")
                        // Normalize the recovered key to uncompressed before deriving address
                        let normalizedRecovered = try service.normalizedWalletPublicKey(recoveredKey)
                        TangemLogger.debug("TangemSigner ▶️ Normalized recovered key (\(normalizedRecovered.count) bytes) = \(normalizedRecovered.tangemHexDescription())")
                        let recoveredAddress = try service.ethereumAddress(fromNormalizedPublicKey: normalizedRecovered)
                        TangemLogger.debug("TangemSigner ▶️ SECP256K1 (compressed=\(compressed)) recovered address=\(recoveredAddress.checksummed) (expected=\(expectedAddress.checksummed))")
                        if recoveredAddress == expectedAddress {
                            TangemLogger.debug("TangemSigner ▶️ Found correct recovery ID: \(recoveryId)")
                            return recoveryId
                        }
                    } catch {
                        TangemLogger.error("TangemSigner ⚠️ Failed to derive address from recovered public key (compressed=\(compressed))", error: error)
                    }
                }
            }
        }

        TangemLogger.debug("TangemSigner ▶️ Falling back to SafeWeb3 recovery")
        for recoveryId in 0...1 {
            do {
                let publicKey = try? EthereumPublicKey(
                    message: Array(hash),
                    v: EthereumQuantity(quantity: BigUInt(recoveryId)),
                    r: EthereumQuantity(rBytes),
                    s: EthereumQuantity(sBytes)
                )

                if let pubKey = publicKey {
                    TangemLogger.debug("TangemSigner ▶️ SafeWeb3 recovered address=\(pubKey.address) for recoveryId=\(recoveryId)")
                    if Address(pubKey.address) == expectedAddress {
                        TangemLogger.debug("TangemSigner ▶️ Found correct recovery ID (fallback): \(recoveryId)")
                        return recoveryId
                    }
                }
            } catch {
                TangemLogger.error("TangemSigner ⚠️ SafeWeb3 recovery error for recoveryId=\(recoveryId)", error: error)
                continue
            }
        }

        TangemLogger.error("TangemSigner ❌ Unable to recover signer for provided signature")
        throw TangemSignerError.invalidSignature
    }


    private func message(for error: Error) -> String {
        if let tangemError = error as? TangemServiceError {
            return tangemError.errorDescription ?? "Tangem operation failed."
        }
        if let signerError = error as? TangemSignerError {
            return signerError.errorDescription ?? "Tangem operation failed."
        }
        return error.localizedDescription
    }

    private func updateUI(for state: State) {
        switch state {
        case .idle:
            activityIndicator.stopAnimating()
            actionButton.isHidden = true
            statusLabel.text = nil
            detailLabel.text = nil

        case .verifyingCard:
            statusLabel.text = "Verifying Tangem Card"
            detailLabel.text = "Hold your Tangem card near the top edge of your iPhone."
            actionButton.isHidden = true
            activityIndicator.startAnimating()

        case .waitingForSignature:
            statusLabel.text = "Ready to Sign"
            detailLabel.text = "Hold your Tangem card again to approve the signature."
            actionButton.isHidden = true
            activityIndicator.startAnimating()

        case .signing:
            statusLabel.text = "Completing Signature"
            detailLabel.text = "Please wait while we process the Tangem signature."
            actionButton.isHidden = true
            activityIndicator.startAnimating()

        case .error(let message):
            statusLabel.text = "Unable to Sign"
            detailLabel.text = message
            activityIndicator.stopAnimating()
            actionButton.isHidden = false
        }
    }

    @objc private func cancelTapped() {
        signingTask?.cancel()
        onClose?()
    }

    @objc private func retryTapped() {
        startSigning()
    }
}

