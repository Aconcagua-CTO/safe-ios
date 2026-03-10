//
//  UnifiedTransactionDetailsViewController.swift
//  Multisig
//
//  Created by GPT-5 Codex on 2026-01-25.
//

import UIKit
import SwiftCryptoTokenFormatter
import WalletConnectSwift
import Version

final class UnifiedTransactionDetailsViewController: LoadableViewController, UITableViewDataSource, UITableViewDelegate {
    private var gatewayService: SafeClientGatewayService {
        safe?.chain?.gatewayService() ?? App.shared.clientGatewayService
    }

    private enum TransactionSource {
        case id(String)
        case safeTxHash(Data)
        case data(SCGModels.TransactionDetails)
    }

    private enum Row {
        case status
        case actionAmount(Int)
        case actionFrom(Int)
        case actionTo(Int)
        case network
        case signatures
        case createdDate(Date)
    }

    private struct ActionDisplay {
        let method: String?
        let fromAddress: Address
        let toAddress: Address
        let amount: UInt256?
        let tokenAddress: Address?
        let isERC20Transfer: Bool
        var amountText: String
    }

    private var rows: [Row] = []
    private var actions: [ActionDisplay] = []
    private var actionAmountRowIndex: [Int: Int] = [:]

    private var tx: SCGModels.TransactionDetails?
    private var txSource: TransactionSource!
    private var reloadDataTask: URLSessionTask?
    private var confirmDataTask: URLSessionTask?
    private var rejectTask: URLSessionTask?
    private var loadSafeInfoDataTask: URLSessionTask?

    private var pendingExecution = false
    private var safe: Safe!
    private var providedSafe: Safe?

    private var ledgerController: LedgerController?
    private var shareButton: UIBarButtonItem!

    private var didTrackScreen: Bool = false
    private var trackedTxStatus: SCGModels.TxStatus?

    private var ledgerKeyInfo: KeyInfo?
    private var keystoneSignFlow: KeystoneSignFlow!

    private var confirmButton: UIButton!
    private var rejectButton: UIButton!
    private var executeButton: UIButton!
    private var actionsContainerView: UIStackView!

    private let tokenMetadataResolver = TokenMetadataResolver.shared
    private let batchLegTitleResolver = BatchLegTitleResolver.shared

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    // MARK: - Signing helpers (robust to missing `signers` in tx-details)
    private var safeOwnerAddresses: [Address] {
        safe.ownersInfo?.map(\.address) ?? []
    }

    private var safeOwnerKeys: [KeyInfo] {
        (try? KeyInfo.keys(addresses: safeOwnerAddresses)) ?? []
    }

    private func remainingSignerKeysForConfirmation() -> [KeyInfo] {
        guard let multisigInfo = tx?.multisigInfo else { return [] }

        let alreadyConfirmed = Set(multisigInfo.confirmations.map { $0.signer.value.address })
        let signersFromTxDetails: [Address] = multisigInfo.signers.map(\.value.address)
        let signersSource: [Address] = signersFromTxDetails.isEmpty ? safeOwnerAddresses : signersFromTxDetails
        let remaining = signersSource.filter { !alreadyConfirmed.contains($0) }

        return (try? KeyInfo.keys(addresses: remaining)) ?? []
    }

    private var needsYourConfirmationForCurrentSafe: Bool {
        guard let tx else { return false }
        guard tx.txStatus.isAwatingConfiramtions else { return false }
        guard let multisigInfo = tx.multisigInfo else { return false }
        guard multisigInfo.needsMoreSignatures else { return false }
        return !remainingSignerKeysForConfirmation().isEmpty
    }

    // MARK: - Init

    convenience init(transactionID: String) {
        self.init(namedClass: Self.superclass())
        txSource = .id(transactionID)
    }

    convenience init(transactionID: String, safe: Safe) {
        self.init(namedClass: Self.superclass())
        txSource = .id(transactionID)
        providedSafe = safe
    }

    convenience init(safeTxHash: Data) {
        self.init(namedClass: Self.superclass())
        txSource = .safeTxHash(safeTxHash)
    }

    convenience init(transaction: SCGModels.TransactionDetails) {
        self.init(namedClass: Self.superclass())
        txSource = .data(transaction)
    }

    convenience init(transaction: SCGModels.TransactionDetails, safe: Safe) {
        self.init(namedClass: Self.superclass())
        txSource = .data(transaction)
        providedSafe = safe
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("ui_tx_details_title", comment: "Title for transaction details screen")

        safe = providedSafe ?? (try! Safe.getSelected()!)
        updateSafeInfo()

        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 48
        tableView.backgroundColor = .backgroundSecondary

        tableView.registerCell(DetailStatusCell.self)
        tableView.registerCell(DetailExpandableTextCell.self)
        tableView.registerCell(DetailConfirmationCell.self)
        tableView.registerCell(NetworkInfoTableViewCell.self)
        tableView.registerCell(DetailAccountCell.self)

        configureActionButtons()

        for notification in [Notification.Name.ownerKeyImported,
                             .ownerKeyRemoved,
                             .ownerKeyUpdated,
                             .chainInfoChanged,
                             .addressbookChanged,
                             .selectedSafeChanged,
                             .transactionDataInvalidated] {
            notificationCenter.addObserver(
                self,
                selector: #selector(lazyReloadData),
                name: notification,
                object: nil)
        }

        notificationCenter.addObserver(
            self,
            selector: #selector(didUpdateTokenWhitelist),
            name: .tokenWhitelistUpdated,
            object: nil
        )

        shareButton = UIBarButtonItem(image: UIImage(named: "ico-share")!.withTintColor(.primary),
                                      style: .plain,
                                      target: self,
                                      action: #selector(didTapShare(_:)))
        navigationItem.rightBarButtonItem = shareButton
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        trackScreen()
    }

    @objc private func didUpdateTokenWhitelist() {
        // Re-resolve ERC-20 decimals/symbol from TokenWhitelist and refresh amounts without refetching tx-details.
        for idx in actions.indices {
            updateActionAmountIfNeeded(for: idx)
        }
    }

    // MARK: - Tracking

    private func trackScreen() {
        if !didTrackScreen, let status = trackedTxStatus {
            Tracker.trackEvent(.transactionsDetails, parameters: [
                "status": status.rawValue
            ])
            didTrackScreen = true
        }
    }

    private func trackScreenWithLoadingFailure() {
        if !didTrackScreen {
            Tracker.trackEvent(.transactionsDetails)
        }
    }

    // MARK: - UI Actions

    @objc private func didTapShare(_ sender: Any) {
        guard let safe = safe,
              let tx = tx else { return }

        let text = App.configuration.services.webAppURL.appendingPathComponent("\(safe.chain!.shortName!):\(safe.displayAddress)/transactions/\(tx.txId)")
        let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        vc.completionWithItemsHandler = { _, success, _, _ in
            if success {
                App.shared.snackbar.show(message: NSLocalizedString("ui_tx_transaction_link_shared_message", comment: "Transaction link shared message"))
            }
        }
        present(vc, animated: true, completion: nil)
    }

    // MARK: - Safe Info

    private func updateSafeInfo() {
        loadSafeInfoDataTask = gatewayService.asyncSafeInfo(safeAddress: safe.addressValue,
                                                            chainId: safe.chain!.id!) { result in
            DispatchQueue.main.async { [weak self] in
                switch result {
                case .success(let safeInfo):
                    self?.safe.update(from: safeInfo)
                case .failure:
                    break
                }
            }
        }
    }

    // MARK: - LoadableViewController

    override func didChangeSelectedSafe() {
        let isVisible = isViewLoaded && view.window != nil
        navigationController?.popViewController(animated: isVisible)
    }

    override func reloadData() {
        super.reloadData()
        reloadDataTask?.cancel()

        guard let chainId = safe.chain?.id else { return }

        switch txSource {
        case .id(let txID):
            reloadDataTask = gatewayService.asyncTransactionDetails(id: txID, chainId: chainId) { [weak self] in
                self?.onLoadingCompleted(result: $0)
            }
        case .safeTxHash(let safeTxHash):
            reloadDataTask = gatewayService.asyncTransactionDetails(safeTxHash: safeTxHash, chainId: chainId) { [weak self] in
                self?.onLoadingCompleted(result: $0)
            }
        case .data(let tx):
            buildRows(from: tx)
            onSuccess()
        case .none:
            preconditionFailure("Developer error: txSource is required")
        }
    }

    private func onLoadingCompleted(result: Result<SCGModels.TransactionDetails, Error>, triggerAutoExecution: Bool = false) {
        switch result {
        case .failure(let error):
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if (error as NSError).code == URLError.cancelled.rawValue &&
                    (error as NSError).domain == NSURLErrorDomain {
                    return
                }
                self.onError(GSError.error(description: NSLocalizedString("ui_tx_failed_load_details_error", comment: "Failed to load transaction details error"),
                                           error: error))
                self.trackScreenWithLoadingFailure()
            }
        case .success(let details):
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let source = self.txSource, case TransactionSource.safeTxHash = source, !details.txId.isEmpty {
                    self.txSource = .id(details.txId)
                }
                self.buildRows(from: details)
                if triggerAutoExecution {
                    self.autoExecuteIfReady(details)
                }
                self.onSuccess()
            }
        }
    }

    private func autoExecuteIfReady(_ transaction: SCGModels.TransactionDetails) {
        AutoExecutionCoordinator.shared.attemptAutoExecute(
            safe: safe,
            transaction: transaction,
            source: "unified_transaction_details_confirm"
        ) { outcome in
            switch outcome {
            case .success:
                App.shared.snackbar.show(message: NSLocalizedString("ui_tx_submit_success_title", comment: "Transaction submitted title"))
            case .failure(let error):
                App.shared.snackbar.show(error: GSError.error(
                    description: NSLocalizedString("ui_tx_submitting_failed_error", comment: "Submitting failed error"),
                    error: error
                ))
            case .skipped:
                break
            }
        }
    }

    override func onSuccess() {
        super.onSuccess()
        showOnly(view: tableView)
    }

    // MARK: - Buttons

    fileprivate func configureActionButtons() {
        actionsContainerView = UIStackView()
        actionsContainerView.axis = .horizontal
        actionsContainerView.distribution = .fillEqually
        actionsContainerView.alignment = .fill
        actionsContainerView.spacing = 20
        actionsContainerView.translatesAutoresizingMaskIntoConstraints = false

        rejectButton = UIButton(type: .custom)
        rejectButton.setText(NSLocalizedString("ui_tx_reject_action", comment: "Reject transaction action"), .filledError)
        rejectButton.addTarget(self, action: #selector(didTapReject), for: .touchUpInside)
        actionsContainerView.addArrangedSubview(rejectButton)

        confirmButton = UIButton(type: .custom)
        confirmButton.setText(NSLocalizedString("ui_tx_confirm_action", comment: "Confirm transaction action"), .filled)
        confirmButton.addTarget(self, action: #selector(didTapConfirm), for: .touchUpInside)
        actionsContainerView.addArrangedSubview(confirmButton)

        executeButton = UIButton(type: .custom)
        executeButton.setText(NSLocalizedString("ui_tx_execute_action", comment: "Execute transaction action"), .filled)
        executeButton.addTarget(self, action: #selector(didTapExecute), for: .touchUpInside)
        actionsContainerView.addArrangedSubview(executeButton)

        view.addSubview(actionsContainerView)
        NSLayoutConstraint.activate([
            actionsContainerView.heightAnchor.constraint(equalToConstant: 56),
            actionsContainerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            actionsContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            actionsContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
    }

    override func showOnly(view: UIView) {
        super.showOnly(view: view)
        actionsContainerView.isHidden = view !== tableView || !showsActionsViewContrainer
        confirmButton.isHidden = !showsConfirmButton
        rejectButton.isHidden = !showsRejectButton
        executeButton.isHidden = !showsExecuteButton

        confirmButton.isEnabled = enableConfirmButton
        rejectButton.isEnabled = enableRejectionButton
        executeButton.isEnabled = !pendingExecution
    }

    private var showsActionsViewContrainer: Bool  {
        (!safeOwnerKeys.isEmpty && (showsRejectButton || showsConfirmButton || showsExecuteButton)) || showsExecuteButton
    }

    private var showsRejectButton: Bool {
        switch self.tx?.txInfo {
        case .rejection(_):
            return false
        default:
            guard let multisigInfo = tx?.multisigInfo,
                  let status = tx?.txStatus,
                  !safeOwnerKeys.isEmpty
            else { return false }

            if status == .awaitingExecution && !multisigInfo.isRejected() && !pendingExecution {
                return true
            } else if status.isAwatingConfiramtions {
                return true
            }
            return false
        }
    }

    private var showsConfirmButton: Bool {
        switch self.tx?.txInfo {
        case .rejection(_):
            if tx!.txStatus.isAwatingConfiramtions,
               let multisigInfo = tx!.multisigInfo,
               !safeOwnerKeys.isEmpty {
                return true
            }
            return false
        default:
            return tx?.txStatus.isAwatingConfiramtions ?? false
        }
    }

    private var showsExecuteButton: Bool {
        guard let nonce = safe.nonce, nonce == tx?.multisigInfo?.nonce.value else {
            return false
        }
        guard let tx = tx else {
            return false
        }
        return needsYourExecution(tx: tx)
    }

    private var enableRejectionButton: Bool {
        if let safeNonce = safe.nonce,
           let txNonce = tx?.multisigInfo?.nonce.value,
           safeNonce > txNonce {
            return false
        }

        if case let SCGModels.TransactionDetails.DetailedExecutionInfo.multisig(multisigTx)? = tx?.detailedExecutionInfo,
           !multisigTx.isRejected(),
           showsRejectButton {
            return true
        }
        return false
    }

    private var enableConfirmButton: Bool {
        needsYourConfirmationForCurrentSafe
    }

    // MARK: - Signing, Rejection, Execution

    @objc private func didTapConfirm() {
        #if DEBUG
        LogService.shared.debug("[DualSignatureFlow] UnifiedTransactionDetailsViewController.didTapConfirm() called")
        if let tx = tx {
            let confirmationsCount = tx.multisigInfo?.confirmations.count ?? 0
            let txStatus = tx.txStatus.rawValue
            LogService.shared.debug("[DualSignatureFlow] - txStatus: \(txStatus)")
            LogService.shared.debug("[DualSignatureFlow] - confirmations count: \(confirmationsCount)")
        }
        #endif

        let signers = remainingSignerKeysForConfirmation()
        guard !signers.isEmpty else {
            App.shared.snackbar.show(message: NSLocalizedString("ui_tx_no_owner_key_available", comment: "No owner key available to sign transaction"))
            return
        }

        #if DEBUG
        LogService.shared.debug("[DualSignatureFlow] - available signer keys count: \(signers.count)")
        for (index, signer) in signers.enumerated() {
            LogService.shared.debug("[DualSignatureFlow] - signer[\(index)]: type=\(signer.keyType.rawValue), address=\(signer.address.checksummed), name=\(signer.displayName)")
        }
        let tangemKeys = signers.filter { $0.keyType == .tangem || $0.keyType == .tangem0 }
        LogService.shared.debug("[DualSignatureFlow] - Tangem card keys in signers: \(tangemKeys.count)")
        #endif

        let descriptionText = NSLocalizedString("ui_tx_confirm_transaction_description", comment: "Confirm transaction description")
        let vc = ChooseOwnerKeyViewController(
            owners: { signers },
            chainID: safe.chain!.id,
            header: .text(description: descriptionText)
        ) {
            [weak self] keyInfo in
            self?.dismiss(animated: true) {
                guard let keyInfo = keyInfo else {
                    #if DEBUG
                    LogService.shared.debug("[DualSignatureFlow] User cancelled key selection in UnifiedTransactionDetailsViewController")
                    #endif
                    return
                }
                #if DEBUG
                LogService.shared.debug("[DualSignatureFlow] User selected key in UnifiedTransactionDetailsViewController: type=\(keyInfo.keyType.rawValue), address=\(keyInfo.address.checksummed), name=\(keyInfo.displayName)")
                #endif
                self?.sign(keyInfo)
            }
        }

        let navigationController = UINavigationController(rootViewController: vc)
        present(navigationController, animated: true)
    }

    @objc private func didTapReject() {
        guard let transaction = tx else { fatalError() }
        let confirmRejectionViewController = RejectionConfirmationViewController(transaction: transaction)
        show(confirmRejectionViewController, sender: self)
    }

    @objc private func didTapExecute() {
        guard let safe = self.safe,
              let chain = self.safe.chain,
              let tx = self.tx else {
            return
        }
        let reviewVC = ReviewExecutionViewController(
            safe: safe,
            chain: chain,
            transaction: tx
        ) { [weak self] in
            self?.dismiss(animated: true, completion: nil)
        } onSuccess: { [weak self] in
            self?.dismiss(animated: true, completion: nil)
        }

        let navigationController = UINavigationController(rootViewController: reviewVC)
        present(navigationController, animated: true)
    }

    private func sign(_ keyInfo: KeyInfo) {
        guard let tx = tx,
              var transaction = Transaction(tx: tx),
              let safeAddress = try? Address(from: safe.address!),
              let chainId = safe.chain?.id,
              let safeTxHash = transaction.safeTxHash?.description else {
            preconditionFailure("Unexpected Error")
        }

        transaction.safe = AddressString(safeAddress)
        transaction.safeVersion = safe.contractVersion != nil ? Version(safe.contractVersion!) : nil
        transaction.chainId = chainId

        switch keyInfo.keyType {
        case .deviceImported, .deviceGenerated, .web3AuthApple, .web3AuthGoogle:
            Wallet.shared.sign(transaction, keyInfo: keyInfo) { [unowned self] result in
                do {
                    let signature = try result.get()
                    confirmAndRefresh(safeTxHash: safeTxHash, signature: signature.hexadecimal, keyInfo: keyInfo)
                } catch {
                    onError(GSError.error(description: NSLocalizedString("ui_tx_failed_confirm_error", comment: "Failed to confirm transaction error"),
                                          error: error))
                }
            }

        case .walletConnect:
            onError(GSError.error(description: NSLocalizedString("ui_walletconnect_legacy_removed_message", comment: "Legacy WalletConnect-for-keys feature removed message")))

        case .ledgerNanoX:
            let request = SignRequest(title: "Confirm Transaction",
                                      tracking: ["action" : "confirm"],
                                      signer: keyInfo,
                                      hexToSign: safeTxHash)
            let vc = LedgerSignerViewController(request: request)

            present(vc, animated: true, completion: {
                Tracker.trackEvent(.reviewExecutionLedger)
            })

            var didSign = false
            vc.completion = { [weak self] signature in
                didSign = true
                self?.confirmAndRefresh(safeTxHash: safeTxHash, signature: signature, keyInfo: keyInfo)
            }

            vc.onClose = { [weak self] in
                if didSign {
                    self?.reloadData()
                }
            }
        case .tangem, .tangem0:
            let request = SignRequest(title: "Confirm Transaction",
                                      tracking: ["action": "confirm"],
                                      signer: keyInfo,
                                      hexToSign: safeTxHash)
            let tangemService: TangemSigningService = keyInfo.keyType == .tangem0 ? Tangem0Service.shared : TangemService.shared
            let vc = TangemSignerViewController(request: request, service: tangemService)

            present(vc, animated: true, completion: {
                Tracker.trackEvent(.reviewExecutionTangem)
            })

            var didSignTangem = false
            vc.completion = { [weak self] signature in
                didSignTangem = true
                self?.confirmAndRefresh(safeTxHash: safeTxHash, signature: signature, keyInfo: keyInfo)
            }

            vc.onClose = { [weak self] in
                if didSignTangem {
                    self?.reloadData()
                }
            }
        case .burner:
            let request = SignRequest(title: "Confirm Transaction",
                                      tracking: ["action": "confirm"],
                                      signer: keyInfo,
                                      hexToSign: safeTxHash)
            let vc = BurnerSignerViewController(request: request)

            present(vc, animated: true, completion: {
                Tracker.trackEvent(.reviewExecutionBurner)
            })

            var didSignBurner = false
            vc.completion = { [weak self] signature in
                didSignBurner = true
                self?.confirmAndRefresh(safeTxHash: safeTxHash, signature: signature, keyInfo: keyInfo)
            }

            vc.onClose = { [weak self] in
                if didSignBurner {
                    self?.reloadData()
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
                    App.shared.snackbar.show(error: GSError.KeystoneSignFailed())
                }
                keystoneSignFlow = nil
            }
            guard let signFlow = KeystoneSignFlow(signInfo: signInfo, completion: signCompletion) else {
                onError(GSError.KeystoneStartSignFailed())
                return
            }

            keystoneSignFlow = signFlow
            keystoneSignFlow.signCompletion = { [weak self] unmarshaledSignature in
                self?.confirmAndRefresh(safeTxHash: safeTxHash, signature: unmarshaledSignature.safeSignature, keyInfo: keyInfo)
            }
            present(flow: keystoneSignFlow)
        }
    }

    private func confirmAndRefresh(safeTxHash: String, signature: String, keyInfo: KeyInfo) {
        super.reloadData()
        confirmDataTask = gatewayService.asyncConfirm(safeTxHash: safeTxHash,
                                                      signature: signature,
                                                      chainId: safe.chain!.id!) { [weak self] result in
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(600)) { [weak self] in
                if case Result.success(_) = result {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .transactionDataInvalidated, object: nil)
                        App.shared.snackbar.show(message: NSLocalizedString("ui_tx_confirmation_submitted_message", comment: "Confirmation submitted message"))
                        Tracker.trackEvent(
                            .userTransactionConfirmed,
                            parameters: TrackingEvent.keyTypeParameters(keyInfo, parameters: ["source": "tx_details"])
                        )
                    }
                }
                self?.onLoadingCompleted(result: result, triggerAutoExecution: true)
            }
        }
    }

    // MARK: - Row building

    private func buildRows(from tx: SCGModels.TransactionDetails) {
        self.tx = tx

        if needsYourConfirmationForCurrentSafe {
            self.tx!.txStatus = .awaitingYourConfirmation
        }

        let transformer = TransactionDataTransformer(safe: self.safe, chain: self.safe.chain!)
        self.tx = transformer.transformed(transaction: self.tx!)

        trackedTxStatus = self.tx?.txStatus
        trackScreen()

        actions = buildActions(from: self.tx!)
        rows = []
        actionAmountRowIndex = [:]

        rows.append(.status)

        for index in actions.indices {
            rows.append(.actionAmount(index))
            actionAmountRowIndex[index] = rows.count - 1
            rows.append(.actionFrom(index))
            rows.append(.actionTo(index))
        }

        rows.append(.network)

        if self.tx?.multisigInfo != nil {
            rows.append(.signatures)
        }

        if let createdAt = self.tx?.multisigInfo?.submittedAt {
            rows.append(.createdDate(createdAt))
        }

    }

    private func buildActions(from tx: SCGModels.TransactionDetails) -> [ActionDisplay] {
        if case let SCGModels.TxInfo.transfer(transferInfo) = tx.txInfo {
            return [actionFromTransfer(transferInfo, chain: safe.chain)]
        }

        if let multiSendActions = extractMultiSendActions(from: tx) {
            return multiSendActions.enumerated().map { index, action in
                actionFromMultiSend(action, index: index)
            }
        }

        if let txData = tx.txData {
            return [actionFromTxData(txData)]
        }

        return []
    }

    private func extractMultiSendActions(from tx: SCGModels.TransactionDetails) -> [SCGModels.DataDecoded.Parameter.ValueDecoded.MultiSendTx]? {
        guard let dataDecoded = tx.txData?.dataDecoded,
              dataDecoded.method == "multiSend",
              let param = dataDecoded.parameters?.first,
              param.type == "bytes",
              case let SCGModels.DataDecoded.Parameter.ValueDecoded.multiSend(multiSendTxs)? = param.valueDecoded else {
            return nil
        }
        return multiSendTxs
    }

    private func actionFromTransfer(_ transferInfo: SCGModels.TxInfo.Transfer, chain: Chain?) -> ActionDisplay {
        let fromAddress = transferInfo.sender.value.address
        let toAddress = transferInfo.recipient.value.address
        let amountText = formattedTransferAmount(transferInfo: transferInfo, chain: chain)
        return ActionDisplay(method: "transfer",
                             fromAddress: fromAddress,
                             toAddress: toAddress,
                             amount: nil,
                             tokenAddress: nil,
                             isERC20Transfer: false,
                             amountText: amountText)
    }

    private func actionFromMultiSend(_ action: SCGModels.DataDecoded.Parameter.ValueDecoded.MultiSendTx, index: Int) -> ActionDisplay {
        let fromAddress = safe.addressValue
        // Prefer decoding ERC-20 transfers from calldata so we can format amounts correctly even when
        // `dataDecoded.method` is missing (which can happen in MultiSend payloads).
        let decodedTransfer = action.data.flatMap { parseERC20Transfer(data: $0) }
        let isTransfer = (action.dataDecoded?.method.lowercased() == "transfer") || (decodedTransfer != nil)

        let resolvedTo: Address = decodedTransfer?.to ?? resolveToAddress(for: action)
        let amount: UInt256? = decodedTransfer?.amount ?? resolveLargestAmount(for: action)
        let tokenAddress = isTransfer ? action.to.address : nil
        let method = isTransfer ? "transfer" : action.dataDecoded?.method
        let amountText = resolveInitialAmountText(amount: amount,
                                                  tokenAddress: tokenAddress,
                                                  isERC20Transfer: isTransfer)

        return ActionDisplay(method: method,
                             fromAddress: fromAddress,
                             toAddress: resolvedTo,
                             amount: amount,
                             tokenAddress: tokenAddress,
                             isERC20Transfer: isTransfer,
                             amountText: amountText)
    }

    private func parseERC20Transfer(data: DataString) -> (to: Address, amount: UInt256)? {
        let bytes = data.data
        // ERC-20 transfer(address,uint256) selector
        let selector = Data([0xA9, 0x05, 0x9C, 0xBB])
        guard bytes.count >= 4 + 32 + 32 else { return nil }
        guard bytes.prefix(4) == selector else { return nil }

        // calldata layout:
        // 0..4   selector
        // 4..36  to (padded)
        // 36..68 amount (uint256)
        let toWord = bytes.subdata(in: 4 ..< 36)
        // last 20 bytes of the 32-byte word
        let toData = toWord.subdata(in: 12 ..< 32)
        guard let to = Address(toData) else { return nil }

        let amountWord = bytes.subdata(in: 36 ..< 68)
        let amount = UInt256(amountWord)

        return (to: to, amount: amount)
    }

    private func actionFromTxData(_ txData: SCGModels.TxData) -> ActionDisplay {
        let fromAddress = safe.addressValue
        let toAddress = resolveToAddress(for: txData)
        let amount = resolveLargestAmount(for: txData)
        let method = txData.dataDecoded?.method
        let isTransfer = method?.lowercased() == "transfer"
        let tokenAddress = isTransfer ? txData.to.value.address : nil
        let amountText = resolveInitialAmountText(amount: amount,
                                                  tokenAddress: tokenAddress,
                                                  isERC20Transfer: isTransfer)

        return ActionDisplay(method: method,
                             fromAddress: fromAddress,
                             toAddress: toAddress,
                             amount: amount,
                             tokenAddress: tokenAddress,
                             isERC20Transfer: isTransfer,
                             amountText: amountText)
    }

    private func resolveToAddress(for action: SCGModels.DataDecoded.Parameter.ValueDecoded.MultiSendTx) -> Address {
        if let dataDecoded = action.dataDecoded {
            if let namedTo = addressParameter(named: "to", in: dataDecoded.parameters) {
                return namedTo
            }
            if let namedRecipient = addressParameter(named: "recipient", in: dataDecoded.parameters) {
                return namedRecipient
            }
            let addressParams = addresses(in: dataDecoded.parameters)
            if dataDecoded.method.lowercased() == "transferfrom", addressParams.count >= 2 {
                return addressParams[1]
            }
            if let first = addressParams.first {
                return first
            }
        }
        return action.to.address
    }

    private func resolveToAddress(for txData: SCGModels.TxData) -> Address {
        if let dataDecoded = txData.dataDecoded {
            if let namedTo = addressParameter(named: "to", in: dataDecoded.parameters) {
                return namedTo
            }
            if let namedRecipient = addressParameter(named: "recipient", in: dataDecoded.parameters) {
                return namedRecipient
            }
            let addressParams = addresses(in: dataDecoded.parameters)
            if dataDecoded.method.lowercased() == "transferfrom", addressParams.count >= 2 {
                return addressParams[1]
            }
            if let first = addressParams.first {
                return first
            }
        }
        return txData.to.value.address
    }

    private func resolveLargestAmount(for action: SCGModels.DataDecoded.Parameter.ValueDecoded.MultiSendTx) -> UInt256? {
        if let dataDecoded = action.dataDecoded {
            let values = uint256Values(in: dataDecoded.parameters)
            return values.max()
        }
        return action.value?.value
    }

    private func resolveLargestAmount(for txData: SCGModels.TxData) -> UInt256? {
        if let dataDecoded = txData.dataDecoded {
            let values = uint256Values(in: dataDecoded.parameters)
            return values.max()
        }
        return txData.value.value
    }

    private func uint256Values(in parameters: [SCGModels.DataDecoded.Parameter]?) -> [UInt256] {
        guard let parameters else { return [] }
        return parameters.flatMap { values in
            extractUInt256Values(from: values.value)
        }
    }

    private func extractUInt256Values(from value: SCGModels.DataDecoded.Parameter.Value) -> [UInt256] {
        switch value {
        case .uint256(let number):
            return [number.value]
        case .array(let values):
            return values.flatMap { extractUInt256Values(from: $0) }
        default:
            return []
        }
    }

    private func addressParameter(named name: String, in parameters: [SCGModels.DataDecoded.Parameter]?) -> Address? {
        guard let parameters else { return nil }
        let match = parameters.first { $0.name.lowercased() == name.lowercased() }
        if case let .address(addressString)? = match?.value {
            return addressString.address
        }
        return nil
    }

    private func addresses(in parameters: [SCGModels.DataDecoded.Parameter]?) -> [Address] {
        guard let parameters else { return [] }
        return parameters.compactMap { param in
            if case let .address(addressString) = param.value {
                return addressString.address
            }
            return nil
        }
    }

    private func formattedTransferAmount(transferInfo: SCGModels.TxInfo.Transfer, chain: Chain?) -> String {
        let tokenFormatter = TokenFormatter()
        let decimalSeparator = Locale.autoupdatingCurrent.decimalSeparator ?? "."
        let thousandSeparator = Locale.autoupdatingCurrent.groupingSeparator ?? ","

        var value: Int256 = 0
        var decimals: UInt256 = 0
        var symbol: String?

        switch transferInfo.transferInfo {
        case .erc20(let erc20TransferInfo):
            value = Int256(erc20TransferInfo.value.value)
            decimals = (try? UInt256(erc20TransferInfo.decimals ?? 0)) ?? 0
            symbol = erc20TransferInfo.tokenSymbol ?? "ERC20"
        case .erc721(let erc721TransferInfo):
            value = 1
            decimals = 0
            symbol = erc721TransferInfo.tokenSymbol ?? "NFT"
        case .nativeCoin(let nativeCoin):
            let coinDecimals = chain?.nativeCurrency?.decimals ?? 0
            value = Int256(nativeCoin.value.value)
            decimals = UInt256(coinDecimals)
            symbol = chain?.nativeCurrency?.symbol
        case .unknown:
            return NSLocalizedString("ui_tx_unknown_token_title", comment: "Unknown token title")
        }

        let decimalAmount = BigDecimal(value, Int(decimals))
        let amount = tokenFormatter.string(from: decimalAmount,
                                           decimalSeparator: decimalSeparator,
                                           thousandSeparator: thousandSeparator,
                                           forcePlusSign: false)
        if let symbol, !symbol.isEmpty {
            return "\(amount) \(symbol)"
        }
        return amount
    }

    private func formattedAmount(_ amount: UInt256, decimals: Int, symbol: String?) -> String {
        let tokenFormatter = TokenFormatter()
        let decimalSeparator = Locale.autoupdatingCurrent.decimalSeparator ?? "."
        let thousandSeparator = Locale.autoupdatingCurrent.groupingSeparator ?? ","

        let decimalAmount = BigDecimal(Int256(amount), decimals)
        let amountString = tokenFormatter.string(from: decimalAmount,
                                                 decimalSeparator: decimalSeparator,
                                                 thousandSeparator: thousandSeparator,
                                                 forcePlusSign: false)
        if let symbol, !symbol.isEmpty {
            return "\(amountString) \(symbol)"
        }
        return amountString
    }

    private func resolveInitialAmountText(amount: UInt256?,
                                          tokenAddress: Address?,
                                          isERC20Transfer: Bool) -> String {
        guard let amount else {
            return NSLocalizedString("ui_tx_not_available_title", comment: "Not available label")
        }
        guard isERC20Transfer,
              let tokenAddress,
              let chain = safe.chain,
              let metadata = tokenMetadataResolver.resolveSynchronously(token: tokenAddress, chain: chain) else {
            return amount.asDecimalString
        }
        return formattedAmount(amount, decimals: metadata.decimals ?? 0, symbol: metadata.symbol)
    }

    private func categoryDisplay(for tx: SCGModels.TransactionDetails) -> (title: String, icon: UIImage?, iconURL: URL?, placeholderAddress: AddressString?, tag: String) {
        var title = ""
        var titleCandidates: [String] = []
        var tag = ""
        var icon: UIImage?
        var imageURL: URL?
        var placeholderAddress: AddressString?
        var compoundMappedTitle: String?

        switch tx.txInfo {
        case .transfer(let transferTx):
            let isOutgoing = transferTx.direction == .outgoing
            title = isOutgoing
                ? NSLocalizedString("ui_tx_outgoing_transfer_title", comment: "Outgoing transfer title")
                : NSLocalizedString("ui_tx_incoming_transfer_title", comment: "Incoming transfer title")
            titleCandidates = [title]
            icon = isOutgoing ? UIImage(named: "ico-outgoing-tx") : UIImage(named: "ico-incomming-tx")?.withTintColor(.success)
        case .settingsChange(_):
            title = NSLocalizedString("ui_tx_modify_settings_title", comment: "Modify settings title")
            titleCandidates = [title]
            icon = UIImage(named: "ico-settings-tx")
        case .custom(let customInfo):
            if let safeAppInfo = tx.safeAppInfo {
                title = safeAppInfo.name
                imageURL = URL(string: safeAppInfo.logoUri)
                tag = NSLocalizedString("ui_tx_app_tag", comment: "Transaction app tag")
                icon = UIImage(named: "ico-custom-tx")
            } else {
                title = customInfo.to.name ?? NSLocalizedString("ui_tx_contract_interaction_title", comment: "Contract interaction title")
                icon = UIImage(named: "ico-custom-tx")
                placeholderAddress = customInfo.to.value
            }
            if let methodName = customInfo.methodName, !methodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                titleCandidates = [methodName, title]
                let contractAddress = customInfo.to.value.description
                compoundMappedTitle = App.shared.transactionNamesRepository
                    .friendlyName(contractAddress: contractAddress, methodName: methodName)
            } else {
                titleCandidates = [title]
            }
            if let legTitle = batchLegTitleResolver.firstLegTitle(from: tx) {
                title = legTitle
                titleCandidates = [legTitle] + titleCandidates
            }
        case .rejection(_):
            title = NSLocalizedString("ui_tx_onchain_rejection_title", comment: "Transaction type label for on-chain rejection")
            titleCandidates = [title]
            icon = UIImage(named: "ico-rejection-tx")
        case .creation(_):
            title = NSLocalizedString("ui_tx_safe_account_created_title", comment: "Transaction type label for Safe Account creation")
            titleCandidates = [title]
            icon = UIImage(named: "ico-settings-tx")
        case .swapOrder(let order):
            title = order.swapOrderDisplayName
            titleCandidates = [title]
            icon = UIImage(named: "ico-custom-tx")
        case .swapTransfer(let order):
            title = order.swapTransferDisplayName
            titleCandidates = [title]
            icon = UIImage(named: "ico-custom-tx")
        case .twapOrder(let order):
            title = order.displayName
            titleCandidates = [title]
            icon = UIImage(named: "ico-custom-tx")
        case .stake(let stake):
            title = stake.displayName
            titleCandidates = [title]
            icon = UIImage(named: "ico-custom-tx")
        case .unknown:
            title = NSLocalizedString("ui_tx_unknown_operation_title", comment: "Unknown operation title")
            titleCandidates = [title]
            icon = UIImage(named: "ico-custom-tx")
        }

        let mapped = compoundMappedTitle ?? titleCandidates.compactMap { App.shared.transactionNamesRepository.friendlyName(for: $0) }.first
        if let mapped, !mapped.isEmpty {
            title = mapped
        }

        return (title, icon, imageURL, placeholderAddress, tag)
    }

    private func updateActionAmountIfNeeded(for index: Int) {
        guard actions.indices.contains(index) else { return }
        let action = actions[index]
        guard action.isERC20Transfer,
              let tokenAddress = action.tokenAddress,
              let amount = action.amount,
              let chain = safe.chain else { return }

        // Resolve via local TokenWhitelist (fast) and format.
        tokenMetadataResolver.resolve(token: tokenAddress, chain: chain) { [weak self] metadata in
            guard let self else { return }
            let formatted = self.formattedAmount(amount,
                                                 decimals: metadata.decimals ?? 0,
                                                 symbol: metadata.symbol)
            if self.actions.indices.contains(index) {
                if self.actions[index].amountText != formatted {
                    self.actions[index].amountText = formatted
                    if let rowIndex = self.actionAmountRowIndex[index] {
                        let indexPath = IndexPath(row: rowIndex, section: 0)
                        if self.tableView.indexPathsForVisibleRows?.contains(indexPath) == true {
                            self.tableView.reloadRows(at: [indexPath], with: .none)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Table view

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let tx = tx else {
            return UITableViewCell()
        }

        let row = rows[indexPath.row]
        switch row {
        case .status:
            let cell = tableView.dequeueCell(DetailStatusCell.self, for: indexPath)
            let display = categoryDisplay(for: tx)
            cell.setTitle(display.title)
            cell.setStatus(tx.txStatus, isReplaced: isReplacedTransaction(tx))
            cell.set(tag: display.tag)
            if let imageURL = display.iconURL, let placeholderAddress = display.placeholderAddress {
                cell.set(contractImageUrl: imageURL, contractAddress: placeholderAddress)
            } else if let imageURL = display.iconURL {
                cell.set(imageUrl: imageURL, placeholder: display.icon)
            } else if let icon = display.icon {
                cell.setIcon(icon)
            } else if let placeholderAddress = display.placeholderAddress {
                cell.set(contractAddress: placeholderAddress)
            }
            return cell
        case .actionAmount(let index):
            let cell = tableView.dequeueCell(DetailExpandableTextCell.self, for: indexPath)
            cell.tableView = tableView
            cell.setTitle(NSLocalizedString("ui_tx_amount_title", comment: "Amount title"))
            cell.setText(actions[index].amountText)
            cell.setExpandableTitle(nil)
            cell.setCopyText(nil)
            return cell
        case .actionFrom(let index):
            let cell = tableView.dequeueCell(DetailAccountCell.self, for: indexPath)
            let address = actions[index].fromAddress
            let (label, imageUri) = NamingPolicy.name(for: address, info: nil, chainId: safe.chain!.id!)
            let title = NSLocalizedString("ui_tx_from_title", comment: "From title")
            cell.setAccount(address: address,
                            label: label,
                            title: title,
                            imageUri: imageUri,
                            browseURL: safe.chain?.browserURL(address: address.checksummed),
                            prefix: safe.chain?.shortName)
            return cell
        case .actionTo(let index):
            let cell = tableView.dequeueCell(DetailAccountCell.self, for: indexPath)
            let address = actions[index].toAddress
            let info = tx.txData?.addressInfoIndex?.values[AddressString(address)]?.addressInfo
            let (label, imageUri) = NamingPolicy.name(for: address, info: info, chainId: safe.chain!.id!)
            let title = NSLocalizedString("ui_tx_to_plain_title", comment: "To title")
            cell.setAccount(address: address,
                            label: label,
                            title: title,
                            imageUri: imageUri,
                            browseURL: safe.chain?.browserURL(address: address.checksummed),
                            prefix: safe.chain?.shortName)
            return cell
        case .network:
            let cell = tableView.dequeueCell(NetworkInfoTableViewCell.self, for: indexPath)
            cell.set(chainId: safe.chain?.id,
                     title: NSLocalizedString("ui_tx_network_title", comment: "Network title"),
                     name: safe.chain?.name)
            return cell
        case .signatures:
            let cell = tableView.dequeueCell(DetailConfirmationCell.self, for: indexPath)
            if let multisigInfo = tx.multisigInfo {
                cell.setConfirmations(multisigInfo.confirmations.map { $0.signer.value.address },
                                      chain: safe.chain!,
                                      required: Int(multisigInfo.confirmationsRequired),
                                      status: tx.txStatus,
                                      executor: multisigInfo.executor?.value.address,
                                      isRejectionTx: tx.txInfo.isRejection,
                                      isReplaced: isReplacedTransaction(tx))
            }
            return cell
        case .createdDate(let date):
            let cell = tableView.dequeueCell(DetailExpandableTextCell.self, for: indexPath)
            cell.tableView = tableView
            cell.setTitle(NSLocalizedString("ui_tx_created_title", comment: "Created date title"))
            cell.setText(dateFormatter.string(from: date))
            cell.setExpandableTitle(nil)
            cell.setCopyText(nil)
            return cell
        }
    }

    private func isReplacedTransaction(_ tx: SCGModels.TransactionDetails) -> Bool {
        guard let safeNonce = safe.nonce else { return false }
        guard tx.txStatus.isInQueue else { return false }
        guard let txNonce = tx.multisigInfo?.nonce.value else { return false }
        return safeNonce > txNonce
    }

    // returns the execution keys valid for executing this transaction
    func executionKeys() -> [KeyInfo] {
        guard tx?.multisigInfo != nil else {
            return []
        }
        guard safe != nil else {
            return []
        }
        guard let allKeys = try? KeyInfo.all(), !allKeys.isEmpty else {
            return []
        }
        let validKeys = allKeys.filter {
            $0.keyType != .ledgerNanoX
        }
        return validKeys
    }

    func needsYourExecution(tx: SCGModels.TransactionDetails) -> Bool {
        if tx.txStatus == .awaitingExecution,
           let multisigInfo = tx.multisigInfo,
           tx.ecdsaConfirmations.count >= multisigInfo.confirmationsRequired,
           !executionKeys().isEmpty {
            return true
        }
        return false
    }

    // MARK: - Address Book (use the transaction's chain, not the globally selected safe)

    override func addToContacts(_ view: AddressInfoView) {
        guard let contact = view.address,
              let txChain = safe.chain,
              let cgChain = SCGModels.Chain.create(from: txChain) else { return }

        let createAddressBookEntryVC = CreateAddressBookEntryViewController()
        createAddressBookEntryVC.inputAddress = contact
        createAddressBookEntryVC.chain = cgChain
        createAddressBookEntryVC.canEditAddress = false

        var inputName: String?

        enum EntryType { case safe, keyInfo, addressBook }
        var entryType: EntryType

        if let s = Safe.by(address: contact.checksummed, chainId: cgChain.id) {
            inputName = s.name
            entryType = .safe
        } else if let keyInfo = (try? KeyInfo.keys(addresses: [contact]))?.first {
            inputName = keyInfo.name
            entryType = .keyInfo
        } else if let existing = AddressBookEntry.uniqueEntries().first(where: { $0.displayAddress.lowercased() == contact.checksummed.lowercased() }) {
            inputName = existing.name
            entryType = .addressBook
        } else {
            inputName = nil
            entryType = .addressBook
        }

        if let name = inputName {
            createAddressBookEntryVC.inputName = name
            createAddressBookEntryVC.screenTitle = "Edit entry"
            createAddressBookEntryVC.actionName = "Save"
        }

        createAddressBookEntryVC.completion = { [unowned createAddressBookEntryVC] (address, name) in
            createAddressBookEntryVC.dismiss(animated: true) {
                switch entryType {
                case .safe:
                    if let s = Safe.by(address: address.checksummed, chainId: createAddressBookEntryVC.chain.id) {
                        s.update(name: name)
                    }
                case .keyInfo:
                    if let keyInfo = try? KeyInfo.keys(addresses: [address]).first {
                        OwnerKeyController.edit(keyInfo: keyInfo, name: name)
                    }
                case .addressBook:
                    fallthrough
                default:
                    AddressBookEntry.addOrUpdateAllSupportedChains(address.checksummed, name: name)
                }
            }
        }
        let nav = ViewControllerFactory.modalWithRibbon(viewController: createAddressBookEntryVC,
                                                        storedChain: txChain)
        present(nav, animated: true)
    }
}

