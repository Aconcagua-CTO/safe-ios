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

        navigationItem.title = "Review"
        navigationItem.backButtonTitle = "Back"


        retryButton.setText("Retry", .filled)
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

        confirmButtonView.actionTitle = "Submit"
        confirmButtonView.state = .normal
        confirmButtonView.set(rejectionEnabled: false)
        
        confirmButtonView.onAction = { [weak self] in
            self?.didConfirm()
        }
    }

    func didConfirm() {
        // Dual-signature flow: auto-pick local, then card.
        let localKeys = DualSignatureKeySelector.localOwnerKeys(for: safe)
        guard let localKey = localKeys.first else {
            App.shared.snackbar.show(message: "No se encuentra la llave local")
            return
        }

        guard let transaction = transactionWithFee(),
              let safeTxHash = transaction.safeTxHash?.description else {
            preconditionFailure("Unexpected Error")
        }

        startConfirm()

        signAndPropose(transaction: transaction, localKey: localKey, safeTxHash: safeTxHash)
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
                self.handleError(error)
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
            self.showError(GSError.error(description: "Failed to create transaction", error: error))
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
        App.shared.snackbar.show(error: error)
        loadingActivityIndicator.isHidden = true
        loadingActivityIndicator.stopAnimating()
        contentContainerView.isHidden = true
        estimationFailedView.isHidden = false
    }

    private func startLoading() {
        loadingActivityIndicator.isHidden = false
        loadingActivityIndicator.startAnimating()
        contentContainerView.isHidden = true
    }

    private func endLoading() {
        loadingActivityIndicator.isHidden = true
        loadingActivityIndicator.stopAnimating()
        contentContainerView.isHidden = false
    }

    private func startConfirm() {
        self.confirmButtonView.state = .loading
    }

    private func endConfirm() {
        self.confirmButtonView.state = .normal
    }

    // MARK: - Dual signature orchestration

    private func signAndPropose(transaction: Transaction, localKey: KeyInfo, safeTxHash: String) {
        Wallet.shared.sign(transaction, keyInfo: localKey) { [unowned self] result in
            do {
                let signature = try result.get()
                proposeTransaction(
                    transaction: transaction,
                    keyInfo: localKey,
                    signature: signature.hexadecimal,
                    safeTxHash: safeTxHash
                )
            } catch {
                App.shared.snackbar.show(error: GSError.error(description: "Failed to confirm transaction",
                                                              error: error))
                endConfirm()
            }
        }
    }

    private func proposeTransaction(transaction: Transaction,
                                    keyInfo: KeyInfo,
                                    signature: String,
                                    safeTxHash: String) {
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
                        App.shared.snackbar.show(error: GSError.error(description: "Failed to create transaction", error: error))
                    case .success(let transactionDetails):
                        NotificationCenter.default.post(name: .transactionDataInvalidated, object: nil)
                        self.handleCardSignatureIfNeeded(proposedTransaction: transactionDetails, safeTxHash: safeTxHash)
                    }
                }
            }
        }
    }

    private func handleCardSignatureIfNeeded(proposedTransaction: SCGModels.TransactionDetails, safeTxHash: String) {
        let cardKeys = DualSignatureKeySelector.cardOwnerKeys(for: safe)
        guard let cardKey = cardKeys.first else {
            // No card key available; leave as-is.
            endConfirm()
            App.shared.snackbar.show(message: "No card key available; transaction proposed with local signature.")
            onSuccess(transaction: proposedTransaction)
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
        let request = SignRequest(title: "Confirm Transaction",
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
                App.shared.snackbar.show(message: "Card signature pending; complete from Queue.")
                self.onSuccess(transaction: proposedTransaction)
            }
        }

        presentModal(vc)
    }

    private func presentBurnerSigner(cardKey: KeyInfo, safeTxHash: String, proposedTransaction: SCGModels.TransactionDetails) {
        let request = SignRequest(title: "Confirm Transaction",
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
                App.shared.snackbar.show(message: "Card signature pending; complete from Queue.")
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
                        App.shared.snackbar.show(error: GSError.error(description: "Failed to add card signature", error: error))
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
                        title: "Safe Account details",
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
        cell.setText("Advanced parameters")
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
        cell.setTitle("Data")
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
