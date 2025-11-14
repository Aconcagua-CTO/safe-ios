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
    
    init(service: TangemService = .shared) {
        self.service = service
        super.init(nibName: nil, bundle: nil)
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
        
        view.backgroundColor = .backgroundSecondary
        navigationItem.title = "Activate Tangem Card"
        navigationItem.largeTitleDisplayMode = .never
        
        setupUI()
        updateUI(for: .idle)
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
        
        configureButton(activateButton, title: "Activate Card", action: #selector(activateTapped))
        configureButton(doneButton, title: "Done", action: #selector(doneTapped))
        configureButton(tryAgainButton, title: "Try Again", action: #selector(tryAgainTapped))
        configureButton(addAsOwnerButton, title: "Add as Owner", action: #selector(addAsOwnerTapped))
        
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
    
    private func updateUI(for state: State) {
        TangemLogger.debug("🔧 ACTIVATION VC: Updating UI for state: \(String(describing: state))")
        
        switch state {
        case .idle:
            statusLabel.text = "Activate Tangem Card"
            detailLabel.text = "Create a new wallet on your Tangem card. The card must be empty (no existing wallets).\n\nThe wallet will be created using hardware-generated randomness for maximum security."
            activityIndicator.stopAnimating()
            activateButton.isHidden = false
            doneButton.isHidden = true
            tryAgainButton.isHidden = true
            addAsOwnerButton.isHidden = true
            
        case .scanning:
            statusLabel.text = "Scanning Card"
            detailLabel.text = "Hold your Tangem card near the top of your iPhone..."
            activityIndicator.startAnimating()
            activateButton.isHidden = true
            doneButton.isHidden = true
            tryAgainButton.isHidden = true
            addAsOwnerButton.isHidden = true
            
        case .creatingWallet:
            statusLabel.text = "Creating Wallet"
            detailLabel.text = """
            Creating a new wallet on your Tangem card…

            Keep the card pressed flat against the top edge of your iPhone until you feel a vibration.
            If iOS shows a tangem.com banner, ignore it and keep the card in place.
            """
            activityIndicator.startAnimating()
            activateButton.isHidden = true
            doneButton.isHidden = true
            tryAgainButton.isHidden = true
            addAsOwnerButton.isHidden = true
            
        case .settingAccessCode:
            statusLabel.text = "Setting Access Code"
            detailLabel.text = "Setting access code on your Tangem card..."
            activityIndicator.startAnimating()
            activateButton.isHidden = true
            doneButton.isHidden = true
            tryAgainButton.isHidden = true
            addAsOwnerButton.isHidden = true
            
        case .success:
            if let info = activatedCardInfo {
                statusLabel.text = "✅ Card Activated Successfully"
                detailLabel.text = """
                Card ID: \(info.cardId.suffix(8))
                Ethereum Address: \(info.ethereumAddress.checksummed)
                Access Code: \(info.accessCodeSet ? "Set" : "Not Set")
                
                The wallet has been created successfully. You can now add it as an owner.
                """
            } else {
                statusLabel.text = "✅ Card Activated Successfully"
                detailLabel.text = "The wallet has been created successfully."
            }
            activityIndicator.stopAnimating()
            activateButton.isHidden = true
            doneButton.isHidden = false
            tryAgainButton.isHidden = true
            addAsOwnerButton.isHidden = false
            
        case .error(let message):
            statusLabel.text = "❌ Activation Failed"
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
        navigationController?.popViewController(animated: true)
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
        
        onActivationComplete?(info)
        navigationController?.popViewController(animated: true)
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
                
                let info = try await service.activateCard(accessCode: nil)
                
                guard !Task.isCancelled else {
                    TangemLogger.debug("🔧 ACTIVATION VC: Activation cancelled")
                    return
                }
                
                TangemLogger.info("🔧 ACTIVATION VC: ✅ Card activation completed successfully")
                TangemLogger.debug("🔧 ACTIVATION VC: - Card ID: \(info.cardId)")
                TangemLogger.debug("🔧 ACTIVATION VC: - Ethereum Address: \(info.ethereumAddress.checksummed)")
                TangemLogger.debug("🔧 ACTIVATION VC: - Access Code Set: \(info.accessCodeSet)")
                
                await MainActor.run {
                    self.activatedCardInfo = info
                    self.state = .success
                }
            } catch {
                guard !Task.isCancelled else { return }
                
                let message = self.message(for: error)
                TangemLogger.error("🔧 ACTIVATION VC: Card activation failed", error: error)
                
                await MainActor.run {
                    self.state = .error(message)
                }
            }
        }
    }
    
    private func message(for error: Error) -> String {
        if let tangemError = error as? TangemServiceError {
            switch tangemError {
            case .nfcUnavailable:
                return "NFC is not available on this device."
            case .userCancelled:
                return "The NFC session ended before activation finished. Keep the Tangem card in place, ignore any tangem.com banner, and wait for the success message."
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

