//
//  TangemActivationViewController.swift
//  Multisig
//
//  Card activation view controller for creating new wallets on Tangem cards
//

import UIKit
import TangemSdk

final class TangemActivationViewController: UIViewController {
    private let service: TangemService
    
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let statusLabel = UILabel()
    private let detailLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let activateButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)
    private let tryAgainButton = UIButton(type: .system)
    private let addAsOwnerButton = UIButton(type: .system)
    
    private var activationTask: Task<Void, Never>?
    private var activatedCardInfo: ActivatedCardInfo?
    
    var onActivationComplete: ((ActivatedCardInfo) -> Void)?
    var onActivationResult: ((Result<ActivatedCardInfo, Error>) -> Void)?
    var onDidClose: (() -> Void)?
    var autoStartActivation: Bool = false
    var shouldSuppressError: ((Error) -> Bool)?
    var activateButtonTitle: String?
    /// Optional access code to set during activation. When non-nil, passed to
    /// `service.activateCard(accessCode:)` so the card stores a non-default PIN,
    /// which disables the firmware's SmartSecurityDelay (15s) on future sessions.
    var accessCode: String?

    init(service: TangemService = .shared, accessCode: String? = nil) {
        self.service = service
        self.accessCode = accessCode
        super.init(nibName: nil, bundle: nil)
    }

    private enum State {
        case idle
        case scanning
        case creatingWallet
        case settingAccessCode
        case success
        case error(String)
    }
    
    private var state: State = .idle {
        didSet { updateUI(for: state) }
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        activationTask?.cancel()
        TangemLogger.debug("🔧 ACTIVATION VC: View controller deallocated")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        TangemLogger.info("🔧 ACTIVATION VC: View controller loaded")
        
        view.backgroundColor = .black
        navigationItem.title = NSLocalizedString("ui_tangem_activate_card_title", comment: "Title for Tangem card activation screen")
        navigationItem.largeTitleDisplayMode = .never
        
        setupUI()
        updateUI(for: .idle)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if autoStartActivation, case .idle = state {
            TangemLogger.info("🔧 ACTIVATION VC: Auto-starting activation")
            performActivation()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        activationTask?.cancel()
        TangemLogger.debug("🔧 ACTIVATION VC: View will disappear, cancelled activation task")
    }
    
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
        
        configureButton(activateButton,
                        title: activateButtonTitle ?? NSLocalizedString("ui_tangem_activate_card_button", comment: "Activate Tangem card button title"),
                        action: #selector(activateTapped))
        configureButton(doneButton,
                        title: NSLocalizedString("button_done", comment: "Done button title"),
                        action: #selector(doneTapped))
        configureButton(tryAgainButton,
                        title: NSLocalizedString("button_retry", comment: "Retry button title"),
                        action: #selector(tryAgainTapped))
        configureButton(addAsOwnerButton,
                        title: NSLocalizedString("ui_tangem_add_as_owner_button", comment: "Add as owner button title"),
                        action: #selector(addAsOwnerTapped))
        
        contentStack.addArrangedSubview(statusLabel)
        contentStack.addArrangedSubview(detailLabel)
        contentStack.addArrangedSubview(activityIndicator)
        
        let buttonStack = UIStackView()
        buttonStack.axis = .vertical
        buttonStack.spacing = 12
        buttonStack.addArrangedSubview(activateButton)
        buttonStack.addArrangedSubview(doneButton)
        buttonStack.addArrangedSubview(tryAgainButton)
        buttonStack.addArrangedSubview(addAsOwnerButton)
        contentStack.addArrangedSubview(buttonStack)
        
        view.addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 32),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 32),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -32),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -32),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -64)
        ])
    }
    
    private func configureButton(_ button: UIButton, title: String, action: Selector) {
        button.setTitle(title, for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }
    
    private func performAddAsOwner(_ info: ActivatedCardInfo) {
        // Prevent double-taps causing duplicate imports / confusing UI.
        addAsOwnerButton.isEnabled = false
        doneButton.isEnabled = false

        onActivationComplete?(info)
        close()
    }

    private func updateUI(for state: State) {
        TangemLogger.debug("🔧 ACTIVATION VC: Updating UI for state: \(String(describing: state))")
        
        switch state {
        case .idle:
            statusLabel.text = NSLocalizedString("ui_tangem_activate_card_title", comment: "Title for Tangem card activation screen")
            detailLabel.text = NSLocalizedString("ui_tangem_activation_intro_detail", comment: "Tangem activation intro detail")
            activityIndicator.stopAnimating()
            activateButton.isHidden = false
            doneButton.isHidden = true
            tryAgainButton.isHidden = true
            addAsOwnerButton.isHidden = true
            
        case .scanning:
            statusLabel.text = NSLocalizedString("ui_tangem_activation_scanning_title", comment: "Tangem activation scanning title")
            detailLabel.text = NSLocalizedString("ui_tangem_card_reader_hold_near_top", comment: "Tangem activation hold near top message")
            activityIndicator.startAnimating()
            activateButton.isHidden = true
            doneButton.isHidden = true
            tryAgainButton.isHidden = true
            addAsOwnerButton.isHidden = true
            
        case .creatingWallet:
            statusLabel.text = NSLocalizedString("ui_tangem_activation_creating_wallet_title", comment: "Tangem activation creating wallet title")
            detailLabel.text = NSLocalizedString("ui_tangem_activation_creating_wallet_detail", comment: "Tangem activation creating wallet detail")
            activityIndicator.startAnimating()
            activateButton.isHidden = true
            doneButton.isHidden = true
            tryAgainButton.isHidden = true
            addAsOwnerButton.isHidden = true
            
        case .settingAccessCode:
            statusLabel.text = NSLocalizedString("ui_tangem_activation_setting_access_code_title", comment: "Tangem activation setting access code title")
            detailLabel.text = NSLocalizedString("ui_tangem_activation_setting_access_code_detail", comment: "Tangem activation setting access code detail")
            activityIndicator.startAnimating()
            activateButton.isHidden = true
            doneButton.isHidden = true
            tryAgainButton.isHidden = true
            addAsOwnerButton.isHidden = true
            
        case .success:
            if let info = activatedCardInfo {
                statusLabel.text = NSLocalizedString("ui_tangem_activation_success_title", comment: "Tangem activation success title")
                let accessCodeStatus = info.accessCodeSet
                    ? NSLocalizedString("ui_tangem_access_code_set", comment: "Tangem access code set")
                    : NSLocalizedString("ui_tangem_access_code_not_set", comment: "Tangem access code not set")
                detailLabel.text = String(
                    format: NSLocalizedString("ui_tangem_activation_success_detail_format", comment: "Tangem activation success detail"),
                    String(info.cardId.suffix(8)),
                    info.ethereumAddress.checksummed,
                    accessCodeStatus
                )
            } else {
                statusLabel.text = NSLocalizedString("ui_tangem_activation_success_title", comment: "Tangem activation success title")
                detailLabel.text = NSLocalizedString("ui_tangem_activation_success_detail_short", comment: "Tangem activation success short detail")
            }
            activityIndicator.stopAnimating()
            activateButton.isHidden = true
            doneButton.isHidden = false
            tryAgainButton.isHidden = true
            addAsOwnerButton.isHidden = false
            
        case .error(let message):
            statusLabel.text = NSLocalizedString("ui_tangem_activation_failed_title", comment: "Tangem activation failed title")
            detailLabel.text = message
            activityIndicator.stopAnimating()
            activateButton.isHidden = true
            doneButton.isHidden = true
            tryAgainButton.isHidden = false
            addAsOwnerButton.isHidden = true
        }
    }
    
    @objc private func activateTapped() {
        TangemLogger.info("🔧 ACTIVATION VC: User tapped activate button")
        performActivation()
    }
    
    @objc private func doneTapped() {
        TangemLogger.info("🔧 ACTIVATION VC: User tapped done button")
        close()
    }
    
    @objc private func tryAgainTapped() {
        TangemLogger.info("🔧 ACTIVATION VC: User tapped try again button")
        state = .idle
    }
    
    @objc private func addAsOwnerTapped() {
        TangemLogger.info("🔧 ACTIVATION VC: User tapped add as owner button")
        guard let info = activatedCardInfo else {
            TangemLogger.error("🔧 ACTIVATION VC: No activation info available")
            return
        }

        performAddAsOwner(info)
    }

    /// Closes this screen whether it's pushed or presented modally.
    private func close(animated: Bool = true) {
        if let nav = navigationController, nav.viewControllers.first != self {
            nav.popViewController(animated: animated)
            onDidClose?()
            return
        }
        // Presented as root of a nav controller (e.g. from Advanced settings) → dismiss.
        dismiss(animated: animated) { [weak self] in
            self?.onDidClose?()
        }
    }
    
    private func performActivation() {
        activationTask?.cancel()
        state = .scanning
        
        activationTask = Task { [weak self] in
            guard let self else { return }
            
            do {
                TangemLogger.info("🔧 ACTIVATION VC: Starting card activation")
                
                // Update state to creating wallet
                await MainActor.run {
                    self.state = .creatingWallet
                }
                
                let info = try await service.activateCard(accessCode: accessCode)
                
                guard !Task.isCancelled else {
                    TangemLogger.debug("🔧 ACTIVATION VC: Activation cancelled")
                    return
                }
                
                TangemLogger.info("🔧 ACTIVATION VC: ✅ Card activation completed successfully")
                TangemLogger.debug("🔧 ACTIVATION VC: - Card ID: \(info.cardId)")
                TangemLogger.debug("🔧 ACTIVATION VC: - Ethereum Address: \(info.ethereumAddress.checksummed)")
                TangemLogger.debug("🔧 ACTIVATION VC: - Access Code Set: \(info.accessCodeSet)")

                // Register the primary card record after activation.
                self.registerPrimaryCardInBackend(info: info)
                
                await MainActor.run {
                    self.activatedCardInfo = info
                    if let onActivationResult = self.onActivationResult {
                        onActivationResult(.success(info))
                        self.close()
                    } else if self.onActivationComplete != nil {
                        self.performAddAsOwner(info)
                    } else {
                        self.state = .success
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                
                let message = self.message(for: error)
                TangemLogger.error("🔧 ACTIVATION VC: Card activation failed", error: error)
                
                await MainActor.run {
                    if let shouldSuppressError = self.shouldSuppressError, shouldSuppressError(error) {
                        self.onActivationResult?(.failure(error))
                        self.close()
                    } else {
                        self.onActivationResult?(.failure(error))
                        self.state = .error(message)
                    }
                }
            }
        }
    }

    private func registerPrimaryCardInBackend(info: ActivatedCardInfo) {
        guard App.shared.authRepository.isAuthenticated() else {
            TangemLogger.debug("🔧 ACTIVATION VC: Skipping primary card registration (user not authenticated)")
            return
        }

        let cardPublicKeyHex = info.cardPublicKey.map { $0.map { String(format: "%02x", $0) }.joined() }
        let walletPublicKeyHex = info.wallet.publicKey.map { String(format: "%02x", $0) }.joined()

        let payload = RegisterPrimaryCardPayload(
            manufacturer: "tangem",
            cardId: info.cardId,
            firmwareLevel: nil,
            state: 1,
            cardPublicKey: cardPublicKeyHex,
            walletPublicKey: walletPublicKeyHex
        )
        let service = PrimaryCardRegistrationService(
            authRepository: App.shared.authRepository,
            logger: LogService.shared
        )

        service.registerPrimaryCard(payload: payload) { result in
            switch result {
            case .success:
                TangemLogger.info("🔧 ACTIVATION VC: Registered primary Tangem card (cardId=\(info.cardId))")
            case .failure(let error):
                TangemLogger.error("🔧 ACTIVATION VC: Failed to register primary Tangem card", error: error)
            }
        }
    }
    
    private func message(for error: Error) -> String {
        if let tangemError = error as? TangemServiceError {
            switch tangemError {
            case .nfcUnavailable:
                return "NFC is not available on this device."
            case .userCancelled:
                return NSLocalizedString("ui_tangem_activation_error_nfc_session_expired", comment: "Tangem activation NFC session expired")
            case .sdkError(let sdkError):
                return sdkError.localizedDescription
            case .underlying(let underlying):
                return underlying.localizedDescription
            default:
                return tangemError.localizedDescription
            }
        }
        return error.localizedDescription
    }
}

