//
//  Tangem0BackupActivationViewController.swift
//  Multisig
//
//  Experimental Tangem0 flow that proves backup-based access code setup.
//  User-paced: each NFC step requires a "Continue" tap, giving CoreNFC
//  time to fully tear down between sessions (avoids NFCReader reuse race).
//

import UIKit
import TangemSdk

final class Tangem0BackupActivationViewController: UIViewController {
    private let accessCode = "abcd1234"

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let statusLabel = UILabel()
    private let detailLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let actionButton = UIButton(type: .system)
    private let retryButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)

    private var flowTask: Task<Void, Never>?
    private var continuationForTap: CheckedContinuation<Void, Never>?

    private var backupSdk: TangemSdk?
    private var backupService: BackupService?
    private var activatedInfo: TangemActivationTask.Result?
    private var firstResetCardId: String?

    private enum FlowError: LocalizedError {
        case ownerImportFailed
        var errorDescription: String? {
            "Backup succeeded, but importing the Tangem0 owner key failed."
        }
    }

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit { flowTask?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        navigationItem.title = "Activate Tangem0 (Backup)"
        navigationItem.largeTitleDisplayMode = .never
        setupUI()
        showIdle()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        flowTask?.cancel()
    }

    // MARK: - UI

    private func setupUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        view.addSubview(scrollView)

        statusLabel.font = .preferredFont(forTextStyle: .title2)
        statusLabel.textColor = .labelPrimary
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center

        detailLabel.font = .preferredFont(forTextStyle: .body)
        detailLabel.textColor = .labelSecondary
        detailLabel.numberOfLines = 0
        detailLabel.textAlignment = .center

        activityIndicator.hidesWhenStopped = true

        configureButton(actionButton, action: #selector(actionTapped))
        configureButton(retryButton, action: #selector(retryTapped))
        configureButton(doneButton, action: #selector(doneTapped))
        retryButton.setTitle(NSLocalizedString("button_retry", comment: ""), for: .normal)
        doneButton.setTitle(NSLocalizedString("button_done", comment: ""), for: .normal)

        contentStack.addArrangedSubview(statusLabel)
        contentStack.addArrangedSubview(detailLabel)
        contentStack.addArrangedSubview(activityIndicator)

        let buttonStack = UIStackView()
        buttonStack.axis = .vertical
        buttonStack.spacing = 12
        buttonStack.addArrangedSubview(actionButton)
        buttonStack.addArrangedSubview(retryButton)
        buttonStack.addArrangedSubview(doneButton)
        contentStack.addArrangedSubview(buttonStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 32),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 32),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -32),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -32),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -64),
        ])
    }

    private func configureButton(_ button: UIButton, action: Selector) {
        button.addTarget(self, action: action, for: .touchUpInside)
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }

    private func showIdle() {
        statusLabel.text = "Tangem0 Backup Activation"
        detailLabel.text = "Resets two cards, links backup, sets access code \(accessCode).\nRequires 2 physical Tangem cards."
        activityIndicator.stopAnimating()
        actionButton.setTitle("Start", for: .normal)
        actionButton.isHidden = false
        retryButton.isHidden = true
        doneButton.isHidden = true
    }

    private func showBusy(step: Int, title: String, detail: String) {
        statusLabel.text = "Step \(step)/8: \(title)"
        detailLabel.text = detail
        activityIndicator.startAnimating()
        actionButton.isHidden = true
        retryButton.isHidden = true
        doneButton.isHidden = true
    }

    private func showWaitForTap(step: Int, nextTitle: String, nextDetail: String) {
        statusLabel.text = "Step \(step)/8 complete"
        detailLabel.text = "Next: \(nextTitle)\n\(nextDetail)\n\nTap Continue when ready."
        activityIndicator.stopAnimating()
        actionButton.setTitle("Continue", for: .normal)
        actionButton.isHidden = false
        retryButton.isHidden = true
        doneButton.isHidden = true
    }

    private func showSuccess() {
        statusLabel.text = "Activation Complete"
        detailLabel.text = "Tangem0 key imported. You can now test signing with access code \(accessCode)."
        activityIndicator.stopAnimating()
        actionButton.isHidden = true
        retryButton.isHidden = true
        doneButton.isHidden = false
    }

    private func showError(_ message: String) {
        statusLabel.text = "Activation Failed"
        detailLabel.text = message
        activityIndicator.stopAnimating()
        actionButton.isHidden = true
        retryButton.isHidden = false
        doneButton.isHidden = true
    }

    // MARK: - Actions

    @objc private func actionTapped() {
        if let c = continuationForTap {
            continuationForTap = nil
            c.resume()
        } else {
            beginFlow()
        }
    }

    @objc private func retryTapped() { showIdle() }
    @objc private func doneTapped() { dismiss(animated: true) }

    private func waitForUserTap() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            self.continuationForTap = c
        }
    }

    // MARK: - Flow

    private func beginFlow() {
        flowTask?.cancel()
        flowTask = Task { [weak self] in
            guard let self else { return }
            do {
                let flowTag = UUID().uuidString.prefix(8).uppercased()
                self.debugLog("FLOW \(flowTag) START (user-paced)")

                self.backupSdk = nil
                self.backupService = nil
                self.activatedInfo = nil
                self.firstResetCardId = nil

                // ── STEP 1: Reset Card 1 ──
                await MainActor.run { self.showBusy(step: 1, title: "Reset Card 1", detail: "Hold CARD 1 near phone") }
                let card1 = try await self.factoryReset(prompt: "Hold CARD 1 near the top of your iPhone to factory reset it.")
                self.firstResetCardId = card1.cardId
                self.debugLog("STEP 1 OK: \(card1.cardId)")

                await MainActor.run { self.showWaitForTap(step: 1, nextTitle: "Reset Card 2", nextDetail: "Hold CARD 2 near phone") }
                await self.waitForUserTap()

                // ── STEP 2: Reset Card 2 ──
                await MainActor.run { self.showBusy(step: 2, title: "Reset Card 2", detail: "Hold CARD 2 near phone") }
                let card2 = try await self.factoryReset(prompt: "Hold CARD 2 near the top of your iPhone to factory reset it.")
                guard card2.cardId != card1.cardId else { throw TangemSdkError.backupCardRequired }
                self.debugLog("STEP 2 OK: \(card2.cardId)")

                await MainActor.run { self.showWaitForTap(step: 2, nextTitle: "Create Wallet", nextDetail: "Hold CARD 1 near phone") }
                await self.waitForUserTap()

                // ── STEP 3: Create wallet on Card 1 ──
                await MainActor.run { self.showBusy(step: 3, title: "Create Wallet", detail: "Hold CARD 1 near phone") }
                let activated = try await self.activatePrimaryWallet()
                self.activatedInfo = activated
                self.debugLog("STEP 3 OK: wallet on \(activated.card.cardId)")

                // Create BackupService for steps 4-8 (fresh SDK, no prior NFC session)
                let freshSdk = TangemSdk()
                freshSdk.config = TangemSdkConfigFactory().makeDefaultConfig()
                self.backupSdk = freshSdk
                let svc = BackupService(sdk: freshSdk, networkService: NetworkService(session: URLSession(configuration: .default), additionalHeaders: [:]))
                svc.discardIncompletedBackup()
                self.backupService = svc

                await MainActor.run { self.showWaitForTap(step: 3, nextTitle: "Read Primary Card", nextDetail: "Hold CARD 1 near phone") }
                await self.waitForUserTap()

                // ── STEP 4: Read Primary Card ──
                await MainActor.run { self.showBusy(step: 4, title: "Read Primary", detail: "Hold CARD 1 near phone") }
                try await self.readPrimaryCard(cardId: activated.card.cardId)
                self.debugLog("STEP 4 OK: primary card read")

                await MainActor.run { self.showWaitForTap(step: 4, nextTitle: "Add Backup Card", nextDetail: "Hold CARD 2 near phone") }
                await self.waitForUserTap()

                // ── STEP 5: Add Backup Card ──
                await MainActor.run { self.showBusy(step: 5, title: "Add Backup Card", detail: "Hold CARD 2 near phone") }
                let backupCard = try await self.addBackupCard()
                guard backupCard.cardId != activated.card.cardId else { throw TangemSdkError.backupCardRequired }
                self.debugLog("STEP 5 OK: backup \(backupCard.cardId)")

                // ── STEP 6: Set Access Code (no NFC) ──
                await MainActor.run { self.showBusy(step: 6, title: "Set Access Code", detail: "Setting access code...") }
                try svc.setAccessCode(self.accessCode)
                self.debugLog("STEP 6 OK: access code set")

                await MainActor.run { self.showWaitForTap(step: 6, nextTitle: "Finalize Primary", nextDetail: "Hold CARD 1 near phone") }
                await self.waitForUserTap()

                // ── STEP 7: Finalize Primary ──
                await MainActor.run { self.showBusy(step: 7, title: "Finalize Primary", detail: "Hold CARD 1 near phone") }
                _ = try await self.proceedBackup()
                self.debugLog("STEP 7 OK: primary finalized")

                await MainActor.run { self.showWaitForTap(step: 7, nextTitle: "Finalize Backup", nextDetail: "Hold CARD 2 near phone") }
                await self.waitForUserTap()

                // ── STEP 8: Finalize Backup ──
                await MainActor.run { self.showBusy(step: 8, title: "Finalize Backup", detail: "Hold CARD 2 near phone") }
                let finalCard = try await self.proceedBackup()
                self.debugLog("STEP 8 OK: backup finalized \(finalCard.cardId)")

                // ── Import key ──
                guard let primaryWallet = activated.card.wallets.first(where: { $0.curve == .secp256k1 }) ?? activated.card.wallets.first else {
                    throw TangemSdkError.walletNotFound
                }
                let normalized = try Tangem0Service.shared.normalizedWalletPublicKey(primaryWallet.publicKey)
                let address = try Tangem0Service.shared.ethereumAddress(fromNormalizedPublicKey: normalized)
                let imported = OwnerKeyController.importKey(
                    tangem0CardId: activated.card.cardId,
                    walletPublicKey: primaryWallet.publicKey,
                    address: address,
                    name: "Tangem0 Card \(activated.card.cardId.suffix(8))",
                    derivationPath: nil,
                    walletIndex: primaryWallet.index
                )
                guard imported else { throw FlowError.ownerImportFailed }

                self.debugLog("FLOW \(flowTag) SUCCESS")
                await MainActor.run { self.showSuccess() }

            } catch {
                guard !Task.isCancelled else { return }
                self.debugLog("FLOW FAILED: \(error)")
                if let sdkError = error as? TangemSdkError {
                    self.debugLog("SDK ERROR: code=\(sdkError.code), value=\(sdkError)")
                }
                await MainActor.run { self.showError(self.formatError(error)) }
            }
        }
    }

    // MARK: - NFC Helpers (disposable SDK for steps 1-3)

    private func makeDisposableSdk() -> TangemSdk {
        let sdk = TangemSdk()
        sdk.config = TangemSdkConfigFactory().makeDefaultConfig()
        return sdk
    }

    private func factoryReset(prompt: String) async throws -> Card {
        let sdk = makeDisposableSdk()
        let task = TangemFactoryResetTask()
        let msg = Message(header: nil, body: prompt)
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<Card, Error>) in
            sdk.startSession(with: task, cardId: nil, initialMessage: msg, accessCode: nil) { result in
                _ = sdk
                c.resume(with: result)
            }
        }
    }

    private func activatePrimaryWallet() async throws -> TangemActivationTask.Result {
        let sdk = makeDisposableSdk()
        let task = TangemActivationTask(curve: .secp256k1, accessCode: nil)
        let msg = Message(header: nil, body: "Hold CARD 1 near the top of your iPhone to create wallet.")
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<TangemActivationTask.Result, Error>) in
            sdk.startSession(with: task, cardId: nil, initialMessage: msg, accessCode: nil) { result in
                _ = sdk
                c.resume(with: result)
            }
        }
    }

    // MARK: - NFC Helpers (shared BackupService for steps 4-8)

    private func readPrimaryCard(cardId: String) async throws {
        guard let svc = backupService else { throw TangemSdkError.unknownError }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            svc.readPrimaryCard(cardId: cardId) { c.resume(with: $0) }
        }
    }

    private func addBackupCard() async throws -> Card {
        guard let svc = backupService else { throw TangemSdkError.unknownError }
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<Card, Error>) in
            svc.addBackupCard { c.resume(with: $0) }
        }
    }

    private func proceedBackup() async throws -> Card {
        guard let svc = backupService else { throw TangemSdkError.unknownError }
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<Card, Error>) in
            svc.proceedBackup { c.resume(with: $0) }
        }
    }

    // MARK: - Utilities

    private func formatError(_ error: Error) -> String {
        if let e = error as? TangemServiceError {
            switch e {
            case .nfcUnavailable: return "NFC is not available."
            case .sdkError(let s): return s.localizedDescription
            case .underlying(let u): return u.localizedDescription
            default: return e.localizedDescription
            }
        }
        return error.localizedDescription
    }

    private func debugLog(_ message: String) {
#if DEBUG
        TangemLogger.debug("🧪 TANGEM0 BACKUP: \(message)")
#endif
    }
}
