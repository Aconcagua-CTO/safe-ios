//
//  ReviewSafeTransactionViewController.swift
//  Multisig
//
//  Created by Moaaz on 4/25/22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import UIKit
import Version
import SwiftCryptoTokenFormatter
import SafeAbi
import Solidity

fileprivate protocol SectionItem {}

class ReviewSafeTransactionViewController: UIViewController {
    @IBOutlet internal weak var tableView: UITableView!
    @IBOutlet private weak var retryButton: UIButton!
    @IBOutlet private weak var descriptionLabel: UILabel!
    @IBOutlet private weak var estimationFailedLabel: UILabel!
    @IBOutlet private weak var loadingActivityIndicator: UIActivityIndicatorView!
    @IBOutlet private weak var estimationFailedDescriptionLabel: UILabel!
    @IBOutlet private weak var estimationFailedView: UIView!
    @IBOutlet private weak var contentContainerView: UIView!
    @IBOutlet weak var confirmButtonView: ActivityButtonView!
    @IBOutlet weak var ribbonView: RibbonView!

    private var currentDataTask: URLSessionTask?
    private var keystoneSignFlow: KeystoneSignFlow!
    var trackingEvent: TrackingEvent = .assetsTransferReview

    var safe: Safe!
    var nonce: UInt256String?
    var safeTxGas: UInt256String?
    var minimalNonce: UInt256String?

    private var gatewayService: SafeClientGatewayService {
        safe.chain?.gatewayService() ?? App.shared.clientGatewayService
    }

    var transactionPreview: SCGModels.TrasactionPreview?
    var feeBatchResult: TransactionBatchBuilder.Result?
    var preparedTransaction: Transaction?
    private var simulationTask: URLSessionTask?
    var shouldLoadTransactionPreview: Bool = false

    enum SectionItem {
        case header(UITableViewCell)
        case safeInfo(UITableViewCell)
        case valueChange(UITableViewCell)
        case data(UITableViewCell)
        case transactionType(UITableViewCell)
        case advanced(UITableViewCell)
    }

    var sectionItems = [SectionItem]()

    convenience init(safe: Safe) {
        self.init(namedClass: ReviewSafeTransactionViewController.self)
        self.safe = safe
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        assert(safe != nil)

        navigationItem.title = NSLocalizedString("ui_review_title", comment: "Title for reviewing a transaction before submitting")
        navigationItem.backButtonTitle = NSLocalizedString("button_back", comment: "Back button title")


        retryButton.setText(NSLocalizedString("button_retry", comment: "Retry button title"), .filled)
        descriptionLabel.setStyle(.footnote)

        tableView.registerCell(BorderedInnerTableCell.self)
        tableView.registerCell(DetailAccountCell.self)
        tableView.registerCell(ValueChangeTableViewCell.self)
        tableView.registerCell(DetailExpandableTextCell.self)

        tableView.estimatedRowHeight = 60
        tableView.rowHeight = UITableView.automaticDimension
        tableView.tableFooterView = UIView()

        ribbonView.update(chain: safe.chain)
        loadData()

        confirmButtonView.actionTitle = NSLocalizedString("button_submit", comment: "Submit button title")
        confirmButtonView.state = .normal
        confirmButtonView.set(rejectionEnabled: false)
        
        confirmButtonView.onAction = { [weak self] in
            self?.didConfirm()
        }
    }

    func didConfirm() {
        guard let transaction = transactionWithFee(),
              let safeTxHash = transaction.safeTxHash?.description,
              let safeTxHashData = Data(exactlyHex: safeTxHash),
              let chainId = safe.chain?.id else {
            preconditionFailure("Unexpected Error")
        }

        startConfirm()

        #if DEBUG
        LogService.shared.debug("[DualSignatureFlow] didConfirm() called - safeTxHash: \(safeTxHash), chainId: \(chainId)")
        #endif

        // Check if transaction already exists with confirmations
        let txId = transaction.safe.map { "multisig_\($0.description)_\(safeTxHash)" }
        let detailsRequest: (@escaping (Result<SCGModels.TransactionDetails, Error>) -> Void) -> URLSessionTask? = { completion in
            if let txId {
                return self.gatewayService.asyncTransactionDetails(id: txId, chainId: chainId, completion: completion)
            }
            return self.gatewayService.asyncTransactionDetails(safeTxHash: safeTxHashData, chainId: chainId, completion: completion)
        }

        currentDataTask = detailsRequest { [weak self] result in
            guard let self = self else { return }
            
            #if DEBUG
            switch result {
            case .success(let existingTx):
                let confirmationsCount: Int
                if let multisigInfo = existingTx.multisigInfo {
                    confirmationsCount = multisigInfo.confirmations.count
                } else {
                    confirmationsCount = 0
                }
                let txStatus = existingTx.txStatus.rawValue
                let hasMultisigInfo = existingTx.multisigInfo != nil
                
                LogService.shared.debug("[DualSignatureFlow] Transaction details fetched successfully")
                LogService.shared.debug("[DualSignatureFlow] - txStatus: \(txStatus)")
                LogService.shared.debug("[DualSignatureFlow] - hasMultisigInfo: \(hasMultisigInfo)")
                LogService.shared.debug("[DualSignatureFlow] - confirmations count: \(confirmationsCount)")
                
                if let multisigInfo = existingTx.multisigInfo {
                    let confirmations = multisigInfo.confirmations
                    LogService.shared.debug("[DualSignatureFlow] - confirmation addresses: \(confirmations.map { $0.signer.value.address })")
                }
                
                // Check available signer keys
                if let signers = existingTx.multisigInfo?.signerKeys() {
                    LogService.shared.debug("[DualSignatureFlow] - available signer keys count: \(signers.count)")
                    for (index, signer) in signers.enumerated() {
                        LogService.shared.debug("[DualSignatureFlow] - signer[\(index)]: type=\(signer.keyType.rawValue), address=\(signer.address.checksummed), name=\(signer.displayName)")
                    }
                    
                    // Check specifically for Tangem cards
                    let tangemKeys = signers.filter { $0.keyType == .tangem || $0.keyType == .tangem0 }
                    LogService.shared.debug("[DualSignatureFlow] - Tangem card keys available: \(tangemKeys.count)")
                    for (index, tangemKey) in tangemKeys.enumerated() {
                        LogService.shared.debug("[DualSignatureFlow] - Tangem[\(index)]: address=\(tangemKey.address.checksummed), name=\(tangemKey.displayName)")
                    }
                } else {
                    LogService.shared.debug("[DualSignatureFlow] - signerKeys() returned nil")
                }
                
                // Check all owner keys (not just remaining signers)
                if let allOwnerKeys = try? KeyInfo.owners(safe: self.safe) {
                    let tangemOwnerKeys = allOwnerKeys.filter { $0.keyType == .tangem || $0.keyType == .tangem0 }
                    LogService.shared.debug("[DualSignatureFlow] - Total Tangem owner keys in Safe: \(tangemOwnerKeys.count)")
                    for (index, tangemKey) in tangemOwnerKeys.enumerated() {
                        LogService.shared.debug("[DualSignatureFlow] - Owner Tangem[\(index)]: address=\(tangemKey.address.checksummed), name=\(tangemKey.displayName)")
                    }
                }
                
            case .failure(let error):
                LogService.shared.debug("[DualSignatureFlow] Transaction details fetch failed: \(error.localizedDescription)")
                if let nsError = error as NSError? {
                    LogService.shared.debug("[DualSignatureFlow] - Error code: \(nsError.code), domain: \(nsError.domain)")
                }
            }
            #endif
            
            switch result {
            case .success(let existingTx):
                // Transaction exists - check if it has confirmations
                if let confirmations = existingTx.multisigInfo?.confirmations, !confirmations.isEmpty {
                    #if DEBUG
                    LogService.shared.debug("[DualSignatureFlow] ✅ Transaction has confirmations - using STANDARD confirmation flow")
                    #endif
                    // Use standard flow for existing transaction with confirmations
                    self.confirmExistingTransaction(existingTx: existingTx, safeTxHash: safeTxHash)
                } else {
                    #if DEBUG
                    LogService.shared.debug("[DualSignatureFlow] ⚠️ Transaction exists but NO confirmations - using DUAL SIGNATURE flow")
                    #endif
                    // Transaction exists but no confirmations - use dual signature flow
                    self.proceedWithDualSignatureFlow(transaction: transaction, safeTxHash: safeTxHash)
                }
            case .failure:
                #if DEBUG
                LogService.shared.debug("[DualSignatureFlow] ⚠️ Transaction fetch failed - using DUAL SIGNATURE flow")
                #endif
                // Transaction doesn't exist - use dual signature flow
                self.proceedWithDualSignatureFlow(transaction: transaction, safeTxHash: safeTxHash)
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        TooltipSource.hideAll()
    }

    @IBAction func retryButtonTouched(_ sender: Any) {
        loadData()
    }

    private func loadData() {
        preparedTransaction = nil
        guard
            let transaction = transactionWithFee(),
            let chainId = transaction.chainId,
            let safeAddress = transaction.safe?.address
        else { return }

        if let version = self.safe.semVer, version < Version(1, 3, 0) {
            estimateTransaction(chainId, safeAddress, transaction)
        } else {
            fetchNonces(chainId, safeAddress)
        }
    }
    
    // Requires:
    //  safe.version < 1.3.0
    fileprivate func estimateTransaction(_ chainId: String, _ safeAddress: Address, _ tx: Transaction) {
        startLoading()
        currentDataTask?.cancel()
        
        currentDataTask = gatewayService.asyncTransactionEstimation(
            chainId: chainId,
            safeAddress: safeAddress,
            to: tx.to.address,
            value: tx.value.value,
            data: tx.data?.data,
            operation: tx.operation
        ) { [weak self] result in
            guard let `self` = self else { return }
            switch result {
            case .failure(let error):
                self.handleError(error)
            case .success(let estimationResult):
                self.minimalNonce = estimationResult.currentNonce
                self.nonce = estimationResult.recommendedNonce
                
                if let estimatedSafeTxGas = UInt256(estimationResult.safeTxGas) {
                    self.safeTxGas = UInt256String(estimatedSafeTxGas)
                }
                
                self.handleEstimationSuccess()
            }
        }
    }
    
    // Requires:
    //  safe.version >= 1.3.0
    fileprivate func fetchNonces(_ chainId: String, _ safeAddress: Address) {
        startLoading()
        currentDataTask?.cancel()

        currentDataTask = gatewayService.asyncSafeNonces(
            chainId: chainId,
            safeAddress: safeAddress
        ) { [weak self] result in
            guard let `self` = self else { return }
            switch result {
            case .failure(let error):
                // Some deployments/proxies block the `/nonces` endpoint (e.g. return 403/404).
                // In that case we can fall back to using the Safe's `nonce` from the safe-info
                // endpoint so the user can still create the transaction.
                let nsError = error as NSError
                if nsError.domain == "NetworkError", nsError.code == 403 || nsError.code == 404 {
                    self.currentDataTask = self.gatewayService.asyncSafeInfo(
                        safeAddress: safeAddress,
                        chainId: chainId
                    ) { [weak self] safeInfoResult in
                        guard let self = self else { return }
                        switch safeInfoResult {
                        case .failure(let safeInfoError):
                            self.handleError(safeInfoError)
                        case .success(let info):
                            self.minimalNonce = info.nonce
                            self.nonce = info.nonce
                            self.safeTxGas = nil
                            self.handleEstimationSuccess()
                        }
                    }
                } else {
                    self.handleError(error)
                }
            case .success(let nonces):
                self.minimalNonce = nonces.currentNonce
                self.nonce = nonces.recommendedNonce
                self.safeTxGas = nil
                self.handleEstimationSuccess()
            }
        }
    }

    fileprivate func handleError(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let `self` = self else { return }
            if (error as NSError).code == URLError.cancelled.rawValue &&
                (error as NSError).domain == NSURLErrorDomain {
                return
            }
            self.showError(GSError.error(description: NSLocalizedString("ui_tx_failed_create_error", comment: "Failed to create transaction error"),
                                         error: error))
        }
    }
    
    fileprivate func handleEstimationSuccess() {
        let transactionForPreview = preparedTransaction ?? transactionWithFee()
        if let transaction = transactionForPreview {
            simulateFeeBatch(transaction: transaction)
        }

        if self.shouldLoadTransactionPreview, let transaction = transactionForPreview {
            self.transactionPreview = nil
            
            self.currentDataTask = gatewayService.asyncPreviewTransaction(
                transaction: transaction,
                sender: AddressString(self.safe.addressValue),
                chainId: self.safe.chain!.id!
            ) { result in
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    switch result {
                    case .success(let response):
                        self.transactionPreview = response
                        self.onSuccess()
                    case .failure(let error):
                        self.handleError(error)
                    }
                }
            }
        } else {
            self.onSuccess()
        }
    }

    private func onSuccess() {
        DispatchQueue.main.async {
            self.endLoading()
            self.bindData()
        }
    }

    private func showError(_ error: DetailedLocalizedError) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.showError(error)
            }
            return
        }
        App.shared.snackbar.show(error: error)
        loadingActivityIndicator.isHidden = true
        loadingActivityIndicator.stopAnimating()
        contentContainerView.isHidden = true
        estimationFailedView.isHidden = false
    }

    private func startLoading() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.startLoading()
            }
            return
        }
        loadingActivityIndicator.isHidden = false
        loadingActivityIndicator.startAnimating()
        contentContainerView.isHidden = true
    }

    private func endLoading() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.endLoading()
            }
            return
        }
        loadingActivityIndicator.isHidden = true
        loadingActivityIndicator.stopAnimating()
        contentContainerView.isHidden = false
    }

    private func startConfirm() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.startConfirm()
            }
            return
        }
        self.confirmButtonView.state = .loading
    }

    private func endConfirm() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.endConfirm()
            }
            return
        }
        self.confirmButtonView.state = .normal
    }

    // MARK: - Dual signature orchestration

    private func proceedWithDualSignatureFlow(transaction: Transaction, safeTxHash: String) {
        // Dual-signature flow: auto-pick local, then card.
        let localKeys = DualSignatureKeySelector.localOwnerKeys(for: safe)
        
        #if DEBUG
        LogService.shared.debug("[DualSignatureFlow] ⚠️ proceedWithDualSignatureFlow() called - this should NOT happen for pending transactions!")
        
        // Log available keys
        let cardKeys = DualSignatureKeySelector.cardOwnerKeys(for: safe)
        LogService.shared.debug("[DualSignatureFlow] - Local keys available: \(localKeys.count)")
        LogService.shared.debug("[DualSignatureFlow] - Card keys available: \(cardKeys.count)")
        for (index, cardKey) in cardKeys.enumerated() {
            LogService.shared.debug("[DualSignatureFlow] - Card[\(index)]: type=\(cardKey.keyType.rawValue), address=\(cardKey.address.checksummed), name=\(cardKey.displayName)")
        }
        #endif
        
        guard let localKey = localKeys.first else {
            #if DEBUG
            LogService.shared.debug("[DualSignatureFlow] ❌ No local key found - showing error message")
            #endif
            endConfirm()
            App.shared.snackbar.show(message: NSLocalizedString("ui_tx_no_local_key_error", comment: "Local key not found error"))
            return
        }

        signAndPropose(transaction: transaction, localKey: localKey, safeTxHash: safeTxHash)
    }

    private func signAndPropose(transaction: Transaction, localKey: KeyInfo, safeTxHash: String) {
        Wallet.shared.sign(transaction, keyInfo: localKey) { [unowned self] result in
            do {
                let signature = try result.get()
                proposeTransaction(
                    transaction: transaction,
                    keyInfo: localKey,
                    signature: signature.hexadecimal,
                    safeTxHash: safeTxHash,
                    localKey: localKey
                )
            } catch {
                App.shared.snackbar.show(error: GSError.error(description: NSLocalizedString("ui_tx_failed_confirm_error", comment: "Failed to confirm transaction error"),
                                                              error: error))
                endConfirm()
            }
        }
    }

    private func proposeTransaction(transaction: Transaction,
                                    keyInfo: KeyInfo,
                                    signature: String,
                                    safeTxHash: String,
                                    localKey: KeyInfo) {
        currentDataTask = gatewayService.asyncProposeTransaction(transaction: transaction,
                                                                 sender: AddressString(keyInfo.address),
                                                                 signature: signature,
                                                                 chainId: safe.chain!.id!) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(600)) {
                DispatchQueue.main.async {
                    switch result {
                    case .failure(let error):
                        if (error as NSError).code == URLError.cancelled.rawValue &&
                            (error as NSError).domain == NSURLErrorDomain {
                            return
                        }
                        self.endConfirm()
                        App.shared.snackbar.show(error: GSError.error(description: NSLocalizedString("ui_tx_failed_create_error", comment: "Failed to create transaction error"),
                                                                     error: error))
                    case .success(let transactionDetails):
                        NotificationCenter.default.post(name: .transactionDataInvalidated, object: nil)
                        self.handleCardSignatureIfNeeded(proposedTransaction: transactionDetails,
                                                         safeTxHash: safeTxHash,
                                                         localKey: localKey)
                    }
                }
            }
        }
    }

    private func handleCardSignatureIfNeeded(proposedTransaction: SCGModels.TransactionDetails,
                                             safeTxHash: String,
                                             localKey: KeyInfo) {
        let cardKeys = DualSignatureKeySelector.cardOwnerKeys(for: safe)
        guard let cardKey = cardKeys.first else {
            let usermail = App.shared.authRepository.getCurrentUser()?.email ?? "unknown"
            LogService.shared.info("User (\(usermail)) no card available, falling back to standard transaction confirmation")

            let owners = KeyInfo.owners(safe: safe)
            let candidates = owners.filter { $0.address != localKey.address }
            if candidates.isEmpty {
                // No card key available; leave as-is.
                endConfirm()
                App.shared.snackbar.show(message: NSLocalizedString("ui_tx_no_card_key_available", comment: "No card key available message"))
                onSuccess(transaction: proposedTransaction)
                return
            }

            let descriptionText = NSLocalizedString("ui_tx_confirm_transaction_description", comment: "Confirm transaction description")
            let vc = ChooseOwnerKeyViewController(
                owners: { candidates },
                chainID: safe.chain!.id,
                header: .text(description: descriptionText)
            ) { [weak self] keyInfo in
                self?.dismiss(animated: true) {
                    guard let keyInfo = keyInfo else {
                        self?.endConfirm()
                        return
                    }
                    self?.signExistingTransaction(keyInfo: keyInfo,
                                                  existingTx: proposedTransaction,
                                                  safeTxHash: safeTxHash)
                }
            }

            let navigationController = UINavigationController(rootViewController: vc)
            presentModal(navigationController)
            return
        }

        switch cardKey.keyType {
        case .tangem, .tangem0:
            presentTangemSigner(cardKey: cardKey, safeTxHash: safeTxHash, proposedTransaction: proposedTransaction)
        case .burner:
            presentBurnerSigner(cardKey: cardKey, safeTxHash: safeTxHash, proposedTransaction: proposedTransaction)
        default:
            // Fallback: unsupported card type, finish with proposed tx.
            endConfirm()
            onSuccess(transaction: proposedTransaction)
        }
    }

    private func presentTangemSigner(cardKey: KeyInfo, safeTxHash: String, proposedTransaction: SCGModels.TransactionDetails) {
        let request = SignRequest(title: NSLocalizedString("ui_tx_confirm_transaction_title", comment: "Confirm transaction title"),
                                  tracking: ["action": "confirm"],
                                  signer: cardKey,
                                  hexToSign: safeTxHash)
        let tangemService: TangemSigningService = cardKey.keyType == .tangem0 ? Tangem0Service.shared : TangemService.shared
        let vc = TangemSignerViewController(request: request, service: tangemService)

        var didSign = false

        vc.completion = { [weak self] signature in
            didSign = true
            self?.confirmWithCardSignature(signature: signature, cardKey: cardKey, safeTxHash: safeTxHash, proposedTransaction: proposedTransaction)
        }

        vc.onClose = { [weak self] in
            guard let self = self else { return }
            if !didSign {
                self.endConfirm()
                App.shared.snackbar.show(message: NSLocalizedString("ui_tx_card_signature_pending", comment: "Card signature pending message"))
                self.onSuccess(transaction: proposedTransaction)
            }
        }

        presentModal(vc)
    }

    private func presentBurnerSigner(cardKey: KeyInfo, safeTxHash: String, proposedTransaction: SCGModels.TransactionDetails) {
        let request = SignRequest(title: NSLocalizedString("ui_tx_confirm_transaction_title", comment: "Confirm transaction title"),
                                  tracking: ["action": "confirm"],
                                  signer: cardKey,
                                  hexToSign: safeTxHash)
        let vc = BurnerSignerViewController(request: request)

        var didSign = false

        vc.completion = { [weak self] signature in
            didSign = true
            self?.confirmWithCardSignature(signature: signature, cardKey: cardKey, safeTxHash: safeTxHash, proposedTransaction: proposedTransaction)
        }

        vc.onClose = { [weak self] in
            guard let self = self else { return }
            if !didSign {
                self.endConfirm()
                App.shared.snackbar.show(message: NSLocalizedString("ui_tx_card_signature_pending", comment: "Card signature pending message"))
                self.onSuccess(transaction: proposedTransaction)
            }
        }

        presentModal(vc)
    }

    private func confirmWithCardSignature(signature: String,
                                          cardKey: KeyInfo,
                                          safeTxHash: String,
                                          proposedTransaction: SCGModels.TransactionDetails) {
        currentDataTask = gatewayService.asyncConfirm(safeTxHash: safeTxHash,
                                                      signature: signature,
                                                      chainId: safe.chain!.id!) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(600)) {
                DispatchQueue.main.async {
                    switch result {
                    case .failure(let error):
                        self.endConfirm()
                        App.shared.snackbar.show(error: GSError.error(description: NSLocalizedString("ui_tx_failed_add_card_signature_error", comment: "Failed to add card signature error"),
                                                                     error: error))
                        // Leave proposed tx as is.
                        self.onSuccess(transaction: proposedTransaction)
                    case .success(let confirmedTx):
                        NotificationCenter.default.post(name: .transactionDataInvalidated, object: nil)
                        self.endConfirm()
                        self.onSuccess(transaction: confirmedTx)
                    }
                }
            }
        }
    }

    // MARK: - Standard confirmation flow for existing transactions

    private func confirmExistingTransaction(existingTx: SCGModels.TransactionDetails, safeTxHash: String) {
        #if DEBUG
        LogService.shared.debug("[DualSignatureFlow] confirmExistingTransaction() called")
        #endif
        
        guard let signers = existingTx.multisigInfo?.signerKeys() else {
            #if DEBUG
            LogService.shared.debug("[DualSignatureFlow] ❌ signerKeys() returned nil")
            #endif
            endConfirm()
            App.shared.snackbar.show(message: NSLocalizedString("ui_tx_no_remaining_signers", comment: "No remaining signers message"))
            return
        }

        guard !signers.isEmpty else {
            #if DEBUG
            LogService.shared.debug("[DualSignatureFlow] ❌ signerKeys() returned empty array")
            #endif
            endConfirm()
            App.shared.snackbar.show(message: NSLocalizedString("ui_tx_no_remaining_signers", comment: "No remaining signers message"))
            return
        }

        #if DEBUG
        LogService.shared.debug("[DualSignatureFlow] ✅ Found \(signers.count) available signers - showing ChooseOwnerKeyViewController")
        #endif

        let descriptionText = NSLocalizedString("ui_tx_confirm_transaction_description", comment: "Confirm transaction description")
        let vc = ChooseOwnerKeyViewController(
            owners: { signers },
            chainID: safe.chain!.id,
            header: .text(description: descriptionText)
        ) { [weak self] keyInfo in
            // dismiss presented ChooseOwnerKeyViewController right after receiving the completion
            self?.dismiss(animated: true) {
                guard let keyInfo = keyInfo else {
                    #if DEBUG
                    LogService.shared.debug("[DualSignatureFlow] User cancelled key selection")
                    #endif
                    self?.endConfirm()
                    return
                }
                #if DEBUG
                LogService.shared.debug("[DualSignatureFlow] User selected key: type=\(keyInfo.keyType.rawValue), address=\(keyInfo.address.checksummed), name=\(keyInfo.displayName)")
                #endif
                self?.signExistingTransaction(keyInfo: keyInfo, existingTx: existingTx, safeTxHash: safeTxHash)
            }
        }

        let navigationController = UINavigationController(rootViewController: vc)
        presentModal(navigationController)
    }

    private func signExistingTransaction(keyInfo: KeyInfo, existingTx: SCGModels.TransactionDetails, safeTxHash: String) {
        guard var transaction = Transaction(tx: existingTx),
              let safeAddress = try? Address(from: safe.address!),
              let chainId = safe.chain?.id else {
            endConfirm()
            App.shared.snackbar.show(error: GSError.error(description: NSLocalizedString("ui_tx_failed_prepare_signing_error", comment: "Failed to prepare transaction for signing error")))
            return
        }

        transaction.safe = AddressString(safeAddress)
        transaction.safeVersion = safe.contractVersion != nil ? Version(safe.contractVersion!) : nil
        transaction.chainId = chainId

        switch keyInfo.keyType {
        case .deviceImported, .deviceGenerated, .web3AuthApple, .web3AuthGoogle:
            Wallet.shared.sign(transaction, keyInfo: keyInfo) { [unowned self] result in
                do {
                    let signature = try result.get()
                    confirmExistingTransactionWithSignature(safeTxHash: safeTxHash, signature: signature.hexadecimal, keyInfo: keyInfo)
                } catch {
                    endConfirm()
                    App.shared.snackbar.show(error: GSError.error(description: NSLocalizedString("ui_tx_failed_confirm_error", comment: "Failed to confirm transaction error"),
                                                                 error: error))
                }
            }

        case .walletConnect:
            let signVC = SignatureRequestToWalletViewController(transaction, keyInfo: keyInfo, chain: safe.chain!)
            signVC.onSuccess = { [weak self] signature in
                self?.confirmExistingTransactionWithSignature(safeTxHash: safeTxHash, signature: signature, keyInfo: keyInfo)
            }
            let vc = ViewControllerFactory.pageSheet(viewController: signVC, halfScreen: true)
            presentModal(vc)

        case .ledgerNanoX:
            let request = SignRequest(title: NSLocalizedString("ui_tx_confirm_transaction_title", comment: "Confirm transaction title"),
                                      tracking: ["action": "confirm"],
                                      signer: keyInfo,
                                      hexToSign: safeTxHash)
            let vc = LedgerSignerViewController(request: request)

            presentModal(vc)
            Tracker.trackEvent(.reviewExecutionLedger)

            var didSign = false

            vc.completion = { [weak self] signature in
                didSign = true
                self?.confirmExistingTransactionWithSignature(safeTxHash: safeTxHash, signature: signature, keyInfo: keyInfo)
            }

            vc.onClose = { [weak self] in
                if !didSign {
                    self?.endConfirm()
                }
            }

        case .tangem, .tangem0:
            let request = SignRequest(title: NSLocalizedString("ui_tx_confirm_transaction_title", comment: "Confirm transaction title"),
                                      tracking: ["action": "confirm"],
                                      signer: keyInfo,
                                      hexToSign: safeTxHash)
            let tangemService: TangemSigningService = keyInfo.keyType == .tangem0 ? Tangem0Service.shared : TangemService.shared
            let vc = TangemSignerViewController(request: request, service: tangemService)

            presentModal(vc)
            Tracker.trackEvent(.reviewExecutionTangem)

            var didSignTangem = false

            vc.completion = { [weak self] signature in
                didSignTangem = true
                self?.confirmExistingTransactionWithSignature(safeTxHash: safeTxHash, signature: signature, keyInfo: keyInfo)
            }

            vc.onClose = { [weak self] in
                if !didSignTangem {
                    self?.endConfirm()
                }
            }

        case .burner:
            let request = SignRequest(title: NSLocalizedString("ui_tx_confirm_transaction_title", comment: "Confirm transaction title"),
                                      tracking: ["action": "confirm"],
                                      signer: keyInfo,
                                      hexToSign: safeTxHash)
            let vc = BurnerSignerViewController(request: request)

            presentModal(vc)
            Tracker.trackEvent(.reviewExecutionBurner)

            var didSignBurner = false

            vc.completion = { [weak self] signature in
                didSignBurner = true
                self?.confirmExistingTransactionWithSignature(safeTxHash: safeTxHash, signature: signature, keyInfo: keyInfo)
            }

            vc.onClose = { [weak self] in
                if !didSignBurner {
                    self?.endConfirm()
                }
            }

        case .keystone:
            let signInfo = KeystoneSignInfo(
                signData: transaction.safeTxHash.hash.toHexString(),
                chain: safe.chain,
                keyInfo: keyInfo,
                signType: .personalMessage
            )
            let signCompletion = { [unowned self] (success: Bool) in
                if !success {
                    endConfirm()
                    App.shared.snackbar.show(error: GSError.KeystoneSignFailed())
                }
                keystoneSignFlow = nil
            }
            guard let signFlow = KeystoneSignFlow(signInfo: signInfo, completion: signCompletion) else {
                endConfirm()
                App.shared.snackbar.show(error: GSError.KeystoneStartSignFailed())
                return
            }
            
            keystoneSignFlow = signFlow
            keystoneSignFlow.signCompletion = { [weak self] unmarshaledSignature in
                self?.confirmExistingTransactionWithSignature(safeTxHash: safeTxHash, signature: unmarshaledSignature.safeSignature, keyInfo: keyInfo)
            }
            present(flow: keystoneSignFlow)
        }
    }

    private func confirmExistingTransactionWithSignature(safeTxHash: String, signature: String, keyInfo: KeyInfo) {
        currentDataTask = gatewayService.asyncConfirm(safeTxHash: safeTxHash,
                                                      signature: signature,
                                                      chainId: safe.chain!.id!) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(600)) {
                DispatchQueue.main.async {
                    switch result {
                    case .failure(let error):
                        self.endConfirm()
                        if (error as NSError).code == URLError.cancelled.rawValue &&
                            (error as NSError).domain == NSURLErrorDomain {
                            return
                        }
                        App.shared.snackbar.show(error: GSError.error(description: NSLocalizedString("ui_tx_failed_confirm_error", comment: "Failed to confirm transaction error"),
                                                                     error: error))
                    case .success(let confirmedTx):
                        NotificationCenter.default.post(name: .transactionDataInvalidated, object: nil)
                        self.endConfirm()
                        App.shared.snackbar.show(message: NSLocalizedString("ui_tx_confirmation_submitted_message", comment: "Confirmation submitted message"))
                        Tracker.trackEvent(
                            .userTransactionConfirmed,
                            parameters: TrackingEvent.keyTypeParameters(keyInfo, parameters: ["source": "review_screen"])
                        )
                        self.onSuccess(transaction: confirmedTx)
                    }
                }
            }
        }
    }

    func presentModal(_ vc: UIViewController) {
        present(vc, animated: true) {
            TooltipSource.hideAll()
        }
    }

    func createTransaction() -> Transaction? {
        nil
    }

    func transactionWithFee() -> Transaction? {
        guard var transaction = createTransaction() else { return nil }
        if let batch = TransactionBatchBuilder.build(transaction: transaction, safe: safe) {
            feeBatchResult = batch
            transaction = batch.transaction
        } else {
            feeBatchResult = nil
        }
        preparedTransaction = transaction
        return transaction
    }

    private func simulateFeeBatch(transaction: Transaction) {
        guard let batch = feeBatchResult else {
            TransactionFeeLogger.debug("Skipping simulation: no fee batch result available.")
            return
        }
        guard let chain = safe.chain,
              let safeSolAddress = Sol.Address(maybeData: safe.addressValue.data32) else {
            TransactionFeeLogger.debug("Skipping simulation: missing chain information.")
            return
        }

        simulationTask?.cancel()

        let client = RpcClient(chain: chain)
        let target = Sol.Address(stringLiteral: batch.multiSendAddress.checksummedWithoutPrefix)
        let payload = Sol.Bytes(storage: transaction.data?.data ?? Data())
        let call = GnosisSafe_v1_3_0.simulateAndRevert(targetContract: target, calldataPayload: payload)

        simulationTask = client.eth_call(to: safeSolAddress, input: call) { result in
            switch result {
            case .success:
                TransactionFeeLogger.info("Fee batch simulation succeeded.")
            case .failure(let error):
                TransactionFeeLogger.warning("Fee batch simulation returned error: \(error)")
            }
        }
    }

    func bindData() {
        createSections()
        tableView.reloadData()
    }

    func createSections() {
        sectionItems = [SectionItem.header(headerCell()), SectionItem.advanced(parametersCell())]
    }

    func headerCell() -> UITableViewCell {
        assertionFailure()
        return UITableViewCell()
    }

    func safeInfoCell() -> UITableViewCell {
        let cell = tableView.dequeueCell(DetailAccountCell.self)
        cell.setAccount(address: safe.addressValue,
                        label: safe.name,
                        title: NSLocalizedString("ui_tx_safe_account_details_title", comment: "Safe account details title"),
                        copyEnabled: false,
                        browseURL: nil,
                        prefix: safe.chain!.shortName,
                        titleStyle: .headlineSecondary)
        cell.selectionStyle = .none
        return cell
    }

    func parametersCell() -> UITableViewCell {
        let tableCell = tableView.dequeueCell(BorderedInnerTableCell.self)

        tableCell.selectionStyle = .none
        tableCell.verticalSpacing = 16

        tableCell.tableView.registerCell(DisclosureWithContentCell.self)

        let cell = tableCell.tableView.dequeueCell(DisclosureWithContentCell.self)
        cell.setText(NSLocalizedString("ui_tx_advanced_parameters_title", comment: "Advanced parameters title"))
        cell.selectionStyle = .none
        cell.setContent(nil)

        tableCell.setCells([cell])
        tableCell.onCellTap = { [unowned self] _ in
            Tracker.trackEvent(.userClaimReviewPar)
            self.showEditParameters()
        }

        return tableCell
    }

    func dataCell() -> UITableViewCell {
        guard let transaction = transactionWithFee() else { return UITableViewCell() }

        let cell = tableView.dequeueCell(DetailExpandableTextCell.self)
        let data = transaction.data?.description ?? ""
        cell.tableView = tableView
        cell.setTitle(NSLocalizedString("ui_tx_data_title", comment: "Transaction data title"))
        cell.setText(data)
        cell.setCopyText(data)
        cell.setExpandableTitle("\(transaction.data?.data.count ?? 0) Bytes")
        cell.selectionStyle = .none
        return cell
    }

    private func showEditParameters() {
        guard let nonce = nonce,
              let minimalNonce = minimalNonce else { return }

        let vc = AdvancedParametersViewController(nonce: nonce,
                                                  minimalNonce: minimalNonce.value,
                                                  safeTxGas: safeTxGas,
                                                  trackingEvent: getTrackingEvent()) { [weak self] nonce, safeTxGas in
            guard let `self` = self else { return }
            self.nonce = nonce
            self.safeTxGas = safeTxGas
            self.bindData()
        }
        let ribbon = RibbonViewController(rootViewController: vc)

        presentModal(ViewControllerFactory.modal(viewController: ribbon))
    }

    // Please override in subclasses
    func getTrackingEvent() -> TrackingEvent {
        .assetsTransferAdvancedParams
    }

    func onSuccess(transaction: SCGModels.TransactionDetails) {
        // Check if transaction is ready to execute
        if isReadyToExecute(transaction: transaction) {
            // Navigate to execution screen
            navigateToExecution(transaction: transaction)
        } else {
            // Show success message and dismiss
            showConfirmationSuccess(transaction: transaction)
        }
    }
    
    private func isReadyToExecute(transaction: SCGModels.TransactionDetails) -> Bool {
        guard transaction.txStatus == .awaitingExecution,
              let multisigInfo = transaction.multisigInfo,
              transaction.ecdsaConfirmations.count >= multisigInfo.confirmationsRequired,
              !executionKeys().isEmpty else {
            return false
        }
        return true
    }
    
    private func executionKeys() -> [KeyInfo] {
        guard let safe = safe, let chain = safe.chain else {
            return []
        }
        
        guard let allKeys = try? KeyInfo.all(), !allKeys.isEmpty else {
            return []
        }
        
        let validKeys = allKeys.filter { keyInfo in
            // if it's a wallet connect key which chain doesn't match then do not use it
            if keyInfo.keyType == .walletConnect,
               let chainId = keyInfo.walletConnections?.first?.chainId,
               // when chainId is 0 then it is 'any' chain
               chainId != 0 && String(chainId) != chain.id {
                return false
            }
            // else use the key
            return true
        }
        .filter {
            // filter out ledger until it is supported
            $0.keyType != .ledgerNanoX
        }
        
        return validKeys
    }
    
    private func navigateToExecution(transaction: SCGModels.TransactionDetails) {
        guard let safe = safe,
              let chain = safe.chain else {
            return
        }
        
        let reviewVC = ReviewExecutionViewController(
            safe: safe,
            chain: chain,
            transaction: transaction
        ) { [weak self] in
            self?.dismiss(animated: true, completion: nil)
        } onSuccess: { [weak self] in
            self?.dismiss(animated: true, completion: nil)
        }
        
        let navigationController = UINavigationController(rootViewController: reviewVC)
        present(navigationController, animated: true)
    }
    
    private func showConfirmationSuccess(transaction: SCGModels.TransactionDetails) {
        let successVC = SuccessViewController(
            titleText: NSLocalizedString("ui_tx_confirmation_submitted_title", comment: "Confirmation submitted title"),
            bodyText: NSLocalizedString("ui_tx_confirmation_submitted_body", comment: "Confirmation submitted body"),
            primaryAction: NSLocalizedString("ui_tx_view_details_action", comment: "View details action"),
            secondaryAction: NSLocalizedString("button_done", comment: "Done button title")
        )
        successVC.onDone = { [weak self] isPrimaryAction in
            guard let self = self else { return }
            self.dismiss(animated: true) {
                if isPrimaryAction {
                    NotificationCenter.default.post(
                        name: .initiateTxNotificationReceived,
                        object: self,
                        userInfo: ["transactionDetails": transaction]
                    )
                }
            }
        }
        
        show(successVC, sender: self)
    }
}

extension ReviewSafeTransactionViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sectionItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = sectionItems[indexPath.row]
        switch item {
        case SectionItem.header(let cell): return cell
        case SectionItem.safeInfo(let cell): return cell
        case SectionItem.advanced(let cell): return cell
        case SectionItem.valueChange(let cell): return cell
        case SectionItem.data(let cell): return cell
        default: return UITableViewCell()
        }
    }
}
