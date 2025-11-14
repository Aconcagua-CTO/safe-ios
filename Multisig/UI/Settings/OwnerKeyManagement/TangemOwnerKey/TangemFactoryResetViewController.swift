//
//  TangemFactoryResetViewController.swift
//  Multisig
//
//  Factory reset view controller for Tangem cards
//  ⚠️ WARNING: This operation is IRREVERSIBLE and will cause PERMANENT DATA LOSS!
//

import UIKit
import TangemSdk

final class TangemFactoryResetViewController: UIViewController {
    private let service: TangemService
    
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let warningLabel = UILabel()
    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let initiateButton = UIButton(type: .system)
    private let confirmButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)
    private let tryAgainButton = UIButton(type: .system)
    
    private var resetTask: Task<Void, Never>?
    
    private enum State {
        case idle
        case confirmationRequired
        case inProgress
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
        resetTask?.cancel()
        TangemLogger.debug("🔥 FACTORY RESET VC: View controller deallocated")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        TangemLogger.info("🔥 FACTORY RESET VC: View controller loaded")
        
        view.backgroundColor = .backgroundSecondary
        navigationItem.title = "Factory Reset Tangem Card"
        navigationItem.largeTitleDisplayMode = .never
        
        setupUI()
        updateUI(for: .idle)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        resetTask?.cancel()
        TangemLogger.debug("🔥 FACTORY RESET VC: View will disappear, cancelled reset task")
    }
    
    private func setupUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        view.addSubview(scrollView)
        
        warningLabel.font = .preferredFont(forTextStyle: .title3)
        warningLabel.textColor = .systemRed
        warningLabel.numberOfLines = 0
        warningLabel.textAlignment = .center
        warningLabel.text = "⚠️ WARNING"
        
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.textColor = .labelPrimary
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        
        activityIndicator.hidesWhenStopped = true
        
        configureButton(initiateButton, title: "Start Factory Reset", action: #selector(initiateTapped))
        configureButton(confirmButton, title: "Confirm Factory Reset", action: #selector(confirmTapped))
        configureButton(cancelButton, title: "Cancel", action: #selector(cancelTapped))
        configureButton(doneButton, title: "Done", action: #selector(doneTapped))
        configureButton(tryAgainButton, title: "Try Again", action: #selector(tryAgainTapped))
        
        contentStack.addArrangedSubview(warningLabel)
        contentStack.addArrangedSubview(statusLabel)
        contentStack.addArrangedSubview(activityIndicator)
        
        let buttonStack = UIStackView()
        buttonStack.axis = .vertical
        buttonStack.spacing = 12
        buttonStack.addArrangedSubview(initiateButton)
        buttonStack.addArrangedSubview(confirmButton)
        buttonStack.addArrangedSubview(cancelButton)
        buttonStack.addArrangedSubview(doneButton)
        buttonStack.addArrangedSubview(tryAgainButton)
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
        TangemLogger.debug("🔥 FACTORY RESET VC: Updating UI for state: \(String(describing: state))")
        
        switch state {
        case .idle:
            warningLabel.isHidden = false
            statusLabel.text = "Factory reset will permanently delete ALL data on your Tangem card, including all wallets and private keys. This operation cannot be undone."
            activityIndicator.stopAnimating()
            initiateButton.isHidden = false
            confirmButton.isHidden = true
            cancelButton.isHidden = true
            doneButton.isHidden = true
            tryAgainButton.isHidden = true
            
        case .confirmationRequired:
            warningLabel.isHidden = false
            statusLabel.text = "⚠️ FINAL WARNING ⚠️\n\nThis will PERMANENTLY DELETE all wallets and data on your Tangem card. This action cannot be undone.\n\nAre you absolutely sure you want to continue?"
            activityIndicator.stopAnimating()
            initiateButton.isHidden = true
            confirmButton.isHidden = false
            cancelButton.isHidden = false
            doneButton.isHidden = true
            tryAgainButton.isHidden = true
            
        case .inProgress:
            warningLabel.isHidden = true
            statusLabel.text = "Resetting card to factory settings...\n\nPlease hold your Tangem card near the top of your iPhone.\n\n⚠️ Do not remove the card until the process is complete."
            activityIndicator.startAnimating()
            initiateButton.isHidden = true
            confirmButton.isHidden = true
            cancelButton.isHidden = true
            doneButton.isHidden = true
            tryAgainButton.isHidden = true
            
        case .success:
            warningLabel.isHidden = true
            statusLabel.text = "✅ Factory reset completed successfully!\n\nThe card has been reset to factory settings. All wallets and data have been permanently deleted."
            activityIndicator.stopAnimating()
            initiateButton.isHidden = true
            confirmButton.isHidden = true
            cancelButton.isHidden = true
            doneButton.isHidden = false
            tryAgainButton.isHidden = true
            
        case .error(let message):
            warningLabel.isHidden = false
            statusLabel.text = "❌ Factory reset failed:\n\n\(message)"
            activityIndicator.stopAnimating()
            initiateButton.isHidden = true
            confirmButton.isHidden = true
            cancelButton.isHidden = true
            doneButton.isHidden = true
            tryAgainButton.isHidden = false
        }
    }
    
    @objc private func initiateTapped() {
        TangemLogger.info("🔥 FACTORY RESET VC: User initiated factory reset")
        state = .confirmationRequired
    }
    
    @objc private func confirmTapped() {
        TangemLogger.info("🔥 FACTORY RESET VC: User confirmed factory reset - STARTING IRREVERSIBLE PROCESS")
        state = .inProgress
        performReset()
    }
    
    @objc private func cancelTapped() {
        TangemLogger.info("🔥 FACTORY RESET VC: User cancelled factory reset")
        state = .idle
    }
    
    @objc private func doneTapped() {
        TangemLogger.info("🔥 FACTORY RESET VC: User completed factory reset flow")
        navigationController?.popViewController(animated: true)
    }
    
    @objc private func tryAgainTapped() {
        TangemLogger.info("🔥 FACTORY RESET VC: User wants to try again")
        state = .idle
    }
    
    private func performReset() {
        resetTask?.cancel()
        
        resetTask = Task { [weak self] in
            guard let self else { return }
            
            do {
                TangemLogger.info("🔥 FACTORY RESET VC: Starting factory reset operation")
                let card = try await service.resetCardToFactory()
                
                guard !Task.isCancelled else {
                    TangemLogger.debug("🔥 FACTORY RESET VC: Reset cancelled")
                    return
                }
                
                TangemLogger.info("🔥 FACTORY RESET VC: ✅ Factory reset completed successfully - Card ID: \(card.cardId)")
                
                await MainActor.run {
                    self.state = .success
                }
            } catch {
                guard !Task.isCancelled else { return }
                
                let message = self.message(for: error)
                TangemLogger.error("🔥 FACTORY RESET VC: Factory reset failed", error: error)
                
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
                return "The operation was cancelled."
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

