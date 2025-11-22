//
//  BurnerSignerViewController.swift
//  Multisig
//
//  Created by GPT-5.1 Codex.
//

import UIKit
import SafeWeb3
import BigInt
import secp256k1

final class BurnerSignerViewController: UINavigationController {
    var completion: ((String) -> Void)?
    var txCompletion: (((v: UInt8, r: Data, s: Data)) -> Void)?
    var onClose: (() -> Void)?
    
    private let request: SignRequest
    private let burnerService: BurnerService
    
    init(request: SignRequest, service: BurnerService = .shared) {
        self.request = request
        self.burnerService = service
        let contentVC = BurnerSignContentViewController(request: request, service: service)
        super.init(rootViewController: contentVC)
        configure(with: contentVC)
        modalPresentationStyle = .formSheet
    }
    
    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func configure(with contentVC: BurnerSignContentViewController) {
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

private enum BurnerSignerError: LocalizedError {
    case missingMetadata
    case invalidHashLength
    case invalidSignature
    case signerMismatch
    
    var errorDescription: String? {
        switch self {
        case .missingMetadata:
            return "Burner card metadata is missing. Please re-import the card."
        case .invalidHashLength:
            return "Expected a 32-byte hash to sign."
        case .invalidSignature:
            return "Burner card returned an invalid signature."
        case .signerMismatch:
            return "The Burner card signed with a different address than expected."
        }
    }
}

private final class BurnerSignContentViewController: UIViewController {
    var onSignedHash: ((String) -> Void)?
    var onSignedTransaction: (((v: UInt8, r: Data, s: Data)) -> Void)?
    var onClose: (() -> Void)?
    
    private enum State {
        case idle
        case waiting
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
    private let service: BurnerService
    
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
    
    init(request: SignRequest, service: BurnerService) {
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
        state = .waiting
        BurnerLogger.debug("BurnerSigner ▶️ Starting signing flow for \(request.signer.address.checksummed)")
        
        signingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let metadata = try self.metadata()
                let tagLog = metadata.tagIdentifier ?? "n/a"
                BurnerLogger.debug("BurnerSigner ▶️ Metadata cardId=\(metadata.cardId) tagId=\(tagLog) slot=\(metadata.slot)")
                
                let payload = try self.makeSigningPayload()
                let signingMessage = "Hold your Burner card near the top of your iPhone to sign."
                
                let result = try await self.service.signHash(cardId: metadata.cardId,
                                                             tagIdentifier: metadata.tagIdentifier,
                                                             slot: metadata.slot,
                                                             hash: payload.hash,
                                                             alertMessage: signingMessage)
                BurnerLogger.debug("BurnerSigner ▶️ Received signature (\(result.signature.count) bytes)")
                
                await MainActor.run { self.state = .signing }
                
                let normalizedKey = try self.normalizePublicKey(result.publicKey)
                let processed = try self.processSignature(result: result,
                                                          hash: payload.hash,
                                                          normalizedPublicKey: normalizedKey,
                                                          expectedAddress: self.request.signer.address)
                
                await MainActor.run {
                    switch (payload.kind, processed) {
                    case (.hash, let .hash(signature)):
                        BurnerLogger.info("Burner signing completed for card \(metadata.cardId) (hash)")
                        self.onSignedHash?(signature)
                    case (.transaction, let .transaction(signature)):
                        BurnerLogger.info("Burner signing completed for card \(metadata.cardId) (transaction)")
                        self.onSignedTransaction?(signature)
                    default:
                        BurnerLogger.error("Burner signing payload mismatch")
                        self.state = .error(BurnerSignerError.invalidSignature.errorDescription ?? "Invalid signature")
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                BurnerLogger.error("Burner signing failed", error: error)
                let message = self.message(for: error)
                await MainActor.run {
                    self.state = .error(message)
                }
            }
        }
    }
    
    private func metadata() throws -> KeyInfo.BurnerKeyMetadata {
        guard let data = request.signer.metadata,
              let metadata = KeyInfo.BurnerKeyMetadata.from(data: data) else {
            throw BurnerSignerError.missingMetadata
        }
        return metadata
    }
    
    private func makeSigningPayload() throws -> SigningPayload {
        switch request.payload {
        case .hash(let hex):
            let data = Data(hexWC: hex)
            if data.count == 32 {
                return SigningPayload(hash: data, kind: .hash)
            }
            let prefix = "\u{19}Ethereum Signed Message:\n\(data.count)".data(using: .utf8) ?? Data()
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
    
    private func processSignature(result: BurnerService.BurnerSignResult,
                                  hash: Data,
                                  normalizedPublicKey: Data,
                                  expectedAddress: Address) throws -> ProcessedSignature {
        guard result.signature.count == 64 else {
            throw BurnerSignerError.invalidSignature
        }
        
        BurnerLogger.debug("BurnerSigner ▶️ Processing signature. Expected address=\(expectedAddress.checksummed)")
        
        let ownerAddress = try ethereumAddress(fromNormalizedPublicKey: normalizedPublicKey)
        guard ownerAddress == expectedAddress else {
            BurnerLogger.error("BurnerSigner ❌ Signer mismatch. Derived address=\(ownerAddress.checksummed) expected=\(expectedAddress.checksummed)")
            throw BurnerSignerError.signerMismatch
        }
        BurnerLogger.debug("BurnerSigner ▶️ Derived signer address matches expected address (\(ownerAddress.checksummed))")
        
        let rSlice = result.signature.prefix(32)
        let sSlice = result.signature.suffix(32)
        let rData = Data(Array(rSlice))
        let sData = Data(Array(sSlice))
        
        let recoveryId = try findRecoveryId(r: rData,
                                            s: sData,
                                            hash: hash,
                                            expectedAddress: ownerAddress)
        BurnerLogger.debug("BurnerSigner ▶️ Recovery ID selected: \(recoveryId)")
        
        let vForSafe = UInt8(27 + recoveryId)
        var signatureData = Data()
        signatureData.append(rData)
        signatureData.append(sData)
        signatureData.append(vForSafe)
        
        let signatureHex = signatureData.toHexStringWithPrefix()
        
        switch request.payload {
        case .hash:
            return .hash(signatureHex)
        case .rawTx:
            return .transaction((v: UInt8(recoveryId), r: rData, s: sData))
        }
    }
    
    private func findRecoveryId(r: Data, s: Data, hash: Data, expectedAddress: Address) throws -> Int {
        let rBytes = Array(r)
        let sBytes = Array(s)
        
        for recoveryId in 0...1 {
            let v = UInt8(27 + recoveryId)
            guard let signature = SECP256K1.marshalSignature(v: v, r: rBytes, s: sBytes) else {
                BurnerLogger.warning("BurnerSigner ⚠️ marshalSignature failed for recoveryId=\(recoveryId)")
                continue
            }
            
            for compressed in [false, true] {
                if let recoveredKey = SECP256K1.recoverPublicKey(hash: hash, signature: signature, compressed: compressed) {
                    do {
                        BurnerLogger.debug("BurnerSigner ▶️ Recovered key (\(recoveredKey.count) bytes)")
                        let normalizedRecovered = try normalizePublicKey(recoveredKey)
                        let recoveredAddress = try ethereumAddress(fromNormalizedPublicKey: normalizedRecovered)
                        if recoveredAddress == expectedAddress {
                            return recoveryId
                        }
                    } catch {
                        BurnerLogger.error("BurnerSigner ⚠️ Failed to derive address from recovered key", error: error)
                    }
                }
            }
        }
        throw BurnerSignerError.invalidSignature
    }
    
    private func normalizePublicKey(_ publicKey: Data) throws -> Data {
        if publicKey.count == 65 {
            return publicKey
        }
        if publicKey.count == 33 {
            guard var secpKey = SECP256K1.parsePublicKey(serializedKey: publicKey),
                  let uncompressed = SECP256K1.serializePublicKey(publicKey: &secpKey, compressed: false) else {
                throw BurnerSignerError.invalidSignature
            }
            return uncompressed
        }
        throw BurnerSignerError.invalidSignature
    }
    
    private func ethereumAddress(fromNormalizedPublicKey publicKey: Data) throws -> Address {
        guard publicKey.count == 65 else {
            throw BurnerSignerError.invalidSignature
        }
        let hash = EthHasher.hash(publicKey.dropFirst())
        let addressBytes = Data(Array(hash.suffix(20)))
        guard let address = Address(addressBytes) else {
            throw BurnerSignerError.signerMismatch
        }
        return address
    }
    
    private func message(for error: Error) -> String {
        if let burnerError = error as? BurnerService.BurnerServiceError {
            return burnerError.errorDescription ?? "Burner card interaction failed."
        }
        if let signerError = error as? BurnerSignerError {
            return signerError.errorDescription ?? "Burner card interaction failed."
        }
        return error.localizedDescription
    }
    
    private func updateUI(for state: State) {
        switch state {
        case .idle:
            statusLabel.text = nil
            detailLabel.text = nil
            activityIndicator.stopAnimating()
            actionButton.isHidden = true
        case .waiting:
            statusLabel.text = "Ready to Sign"
            detailLabel.text = "Hold your Burner card near the top edge of your iPhone."
            activityIndicator.startAnimating()
            actionButton.isHidden = true
        case .signing:
            statusLabel.text = "Processing Signature"
            detailLabel.text = "Stay close to the Burner card until the signature is completed."
            activityIndicator.startAnimating()
            actionButton.isHidden = true
        case .error(let message):
            statusLabel.text = "Unable to Sign"
            detailLabel.text = message
            activityIndicator.stopAnimating()
            actionButton.isHidden = false
        }
    }
    
    @objc private func cancelTapped() {
        onClose?()
    }
    
    @objc private func retryTapped() {
        startSigning()
    }
}

