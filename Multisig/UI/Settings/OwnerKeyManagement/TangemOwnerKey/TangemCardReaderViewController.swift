//
//  TangemCardReaderViewController.swift
//  Multisig
//
//  Comprehensive card reader for displaying all Tangem card information
//

import UIKit
import TangemSdk

final class TangemCardReaderViewController: UIViewController {
    private let service: TangemService
    private let scrollView = UIScrollView()
    private let contentView = UIStackView()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let statusLabel = UILabel()
    private let scanButton = UIButton(type: .system)
    
    private var scanTask: Task<Void, Never>?
    private var cardInfo: ComprehensiveCardInfo?
    
    init(service: TangemService = .shared) {
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        scanTask?.cancel()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        TangemLogger.info("📖 CARD READER VC: View controller loaded")
        
        view.backgroundColor = .backgroundSecondary
        navigationItem.title = "Read Tangem Card"
        navigationItem.largeTitleDisplayMode = .never
        
        setupUI()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        scanTask?.cancel()
        TangemLogger.debug("📖 CARD READER VC: View will disappear, cancelled scan task")
    }
    
    private func setupUI() {
        contentView.axis = .vertical
        contentView.spacing = 16
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        view.addSubview(scrollView)
        
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.textColor = .labelSecondary
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        scanButton.setTitle("Scan Card", for: .normal)
        scanButton.addTarget(self, action: #selector(scanTapped), for: .touchUpInside)
        scanButton.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(statusLabel)
        view.addSubview(activityIndicator)
        view.addSubview(scanButton)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: scanButton.topAnchor, constant: -16),
            
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -16),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32),
            
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
            
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -16),
            
            scanButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            scanButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            scanButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        updateUI(state: .idle)
    }
    
    private enum State {
        case idle
        case scanning
        case ready
        case error(String)
    }
    
    private func updateUI(state: State) {
        switch state {
        case .idle:
            statusLabel.text = "Tap 'Scan Card' to read all Tangem card information"
            statusLabel.isHidden = false
            activityIndicator.stopAnimating()
            scanButton.isEnabled = true
            scrollView.isHidden = true
            
        case .scanning:
            statusLabel.text = "Hold your Tangem card near the top of your iPhone..."
            statusLabel.isHidden = false
            activityIndicator.startAnimating()
            scanButton.isEnabled = false
            scrollView.isHidden = true
            
        case .ready:
            statusLabel.isHidden = true
            activityIndicator.stopAnimating()
            scanButton.isEnabled = true
            scanButton.setTitle("Scan Again", for: .normal)
            scrollView.isHidden = false
            
        case .error(let message):
            statusLabel.text = message
            statusLabel.isHidden = false
            activityIndicator.stopAnimating()
            scanButton.isEnabled = true
            scanButton.setTitle("Try Again", for: .normal)
            scrollView.isHidden = true
        }
    }
    
    @objc private func scanTapped() {
        TangemLogger.info("📖 CARD READER VC: Scan button tapped")
        startScan()
    }
    
    private func startScan() {
        scanTask?.cancel()
        updateUI(state: .scanning)
        
        scanTask = Task { [weak self] in
            guard let self else { return }
            
            do {
                TangemLogger.info("📖 CARD READER VC: Starting comprehensive card scan")
                let info = try await service.scanCardComprehensive(forceRefresh: true)
                
                guard !Task.isCancelled else {
                    TangemLogger.debug("📖 CARD READER VC: Scan cancelled")
                    return
                }
                
                await MainActor.run {
                    self.cardInfo = info
                    self.displayCardInfo(info)
                    self.updateUI(state: .ready)
                    TangemLogger.info("📖 CARD READER VC: ✅ Card info displayed successfully")
                }
            } catch {
                guard !Task.isCancelled else { return }
                
                let message = self.message(for: error)
                TangemLogger.error("📖 CARD READER VC: Scan failed", error: error)
                await MainActor.run {
                    self.updateUI(state: .error(message))
                }
            }
        }
    }
    
    private func displayCardInfo(_ info: ComprehensiveCardInfo) {
        // Clear existing content
        contentView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        TangemLogger.debug("📖 CARD READER VC: Displaying card info sections")
        
        // Basic Info Section
        addSection(title: "Basic Information") { stack in
            self.addDetailRow(label: "Card ID", value: info.basicInfo.cardId, to: stack)
            self.addDetailRow(label: "Batch ID", value: info.batchId, to: stack)
            self.addDetailRow(label: "Firmware Version", value: info.basicInfo.firmwareVersion ?? "Unknown", to: stack)
            self.addDetailRow(label: "Manufacturer", value: info.basicInfo.manufacturer ?? "Unknown", to: stack)
            if let date = info.manufactureDate {
                self.addDetailRow(label: "Manufacture Date", value: date, to: stack)
            }
            self.addDetailRow(label: "Issuer", value: info.issuerName, to: stack)
        }
        
        // Security Settings Section
        addSection(title: "Security Settings") { stack in
            self.addDetailRow(label: "Access Code Set", value: info.isAccessCodeSet ? "Yes" : "No", to: stack)
            if let passcodeSet = info.isPasscodeSet {
                self.addDetailRow(label: "Passcode Set", value: passcodeSet ? "Yes" : "No", to: stack)
            } else {
                self.addDetailRow(label: "Passcode Set", value: "Unknown", to: stack)
            }
            self.addDetailRow(label: "Security Delay", value: "\(info.securityDelay) ms", to: stack)
            self.addDetailRow(label: "User Code Recovery", value: info.isUserCodeRecoveryAllowed ? "Allowed" : "Not Allowed", to: stack)
        }
        
        // Card Capabilities Section
        addSection(title: "Card Capabilities") { stack in
            self.addDetailRow(label: "Max Wallets", value: "\(info.maxWalletsCount)", to: stack)
            self.addDetailRow(label: "HD Wallet Allowed", value: info.isHDWalletAllowed ? "Yes" : "No", to: stack)
            self.addDetailRow(label: "Backup Allowed", value: info.isBackupAllowed ? "Yes" : "No", to: stack)
            self.addDetailRow(label: "Keys Import Allowed", value: info.isKeysImportAllowed ? "Yes" : "No", to: stack)
            self.addDetailRow(label: "Files Allowed", value: info.isFilesAllowed ? "Yes" : "No", to: stack)
            self.addDetailRow(label: "Supported Encryption Modes", value: info.supportedEncryptionModes.joined(separator: ", "), to: stack)
        }
        
        // PIN Management Section
        addSection(title: "PIN Management") { stack in
            self.addDetailRow(label: "Set Access Code Allowed", value: info.isSettingAccessCodeAllowed ? "Yes" : "No", to: stack)
            self.addDetailRow(label: "Set Passcode Allowed", value: info.isSettingPasscodeAllowed ? "Yes" : "No", to: stack)
            self.addDetailRow(label: "Remove User Codes Allowed", value: info.isRemovingUserCodesAllowed ? "Yes" : "No", to: stack)
        }
        
        // Backup Status Section
        if let backupStatus = info.backupStatus {
            addSection(title: "Backup Status") { stack in
                self.addDetailRow(label: "Status", value: backupStatus.description, to: stack)
            }
        }
        
        // Terminal Section
        addSection(title: "Terminal") { stack in
            self.addDetailRow(label: "Linked Terminal Status", value: info.linkedTerminalStatus, to: stack)
            self.addDetailRow(label: "Linked Terminal Enabled", value: info.isLinkedTerminalEnabled ? "Yes" : "No", to: stack)
        }
        
        // Card Public Key Section
        addSection(title: "Card Public Key") { stack in
            let keyHex = info.cardPublicKey.map { String(format: "%02x", $0) }.joined()
            let truncated = String(keyHex.prefix(20)) + "..." + String(keyHex.suffix(20))
            self.addDetailRow(label: "Public Key", value: "0x\(truncated)", to: stack)
        }
        
        // Wallets Section
        if !info.comprehensiveWallets.isEmpty {
            addSection(title: "Wallets (\(info.comprehensiveWallets.count))") { stack in
                for (index, walletInfo) in info.comprehensiveWallets.enumerated() {
                    self.addWalletSection(walletInfo: walletInfo, index: index, to: stack)
                }
            }
        } else {
            addSection(title: "Wallets") { stack in
                self.addDetailRow(label: "Status", value: "No wallets found", to: stack)
            }
        }
    }
    
    private func addSection(title: String, content: (UIStackView) -> Void) {
        let sectionStack = UIStackView()
        sectionStack.axis = .vertical
        sectionStack.spacing = 12
        sectionStack.isLayoutMarginsRelativeArrangement = true
        sectionStack.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        
        let titleLabel = UILabel()
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .labelPrimary
        titleLabel.text = title
        
        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 10
        
        content(contentStack)
        
        sectionStack.addArrangedSubview(titleLabel)
        sectionStack.addArrangedSubview(contentStack)
        contentView.addArrangedSubview(sectionStack)
    }
    
    private func addDetailRow(label: String, value: String, to stack: UIStackView) {
        let rowStack = UIStackView()
        rowStack.axis = .vertical
        rowStack.spacing = 4
        
        let labelView = UILabel()
        labelView.font = .preferredFont(forTextStyle: .caption1)
        labelView.textColor = .labelSecondary
        labelView.text = label
        
        let valueView = UILabel()
        valueView.font = .preferredFont(forTextStyle: .body)
        valueView.textColor = .labelPrimary
        valueView.text = value
        valueView.numberOfLines = 0
        
        rowStack.addArrangedSubview(labelView)
        rowStack.addArrangedSubview(valueView)
        
        stack.addArrangedSubview(rowStack)
    }
    
    private func addWalletSection(walletInfo: ComprehensiveWalletInfo, index: Int, to stack: UIStackView) {
        let walletStack = UIStackView()
        walletStack.axis = .vertical
        walletStack.spacing = 8
        
        let walletTitle = UILabel()
        walletTitle.font = .preferredFont(forTextStyle: .subheadline)
        walletTitle.textColor = .labelPrimary
        walletTitle.text = "Wallet #\(index + 1)"
        walletStack.addArrangedSubview(walletTitle)
        
        do {
            let normalizedKey = try service.normalizedWalletPublicKey(walletInfo.wallet.publicKey)
            let address = try service.ethereumAddress(fromNormalizedPublicKey: normalizedKey)
            addDetailRow(label: "Ethereum Address", value: address.checksummed, to: walletStack)

            let keyHex = walletInfo.wallet.publicKey.tangemHexDescription(prefix: true)
            let logLine = "Tangem card wallet index=\(walletInfo.wallet.index) publicKey=\(keyHex) address=\(address.checksummed)"
            LogService.shared.info("[TangemCardReader] \(logLine)")
            NSLog("[TangemCardReader] %@", logLine)
        } catch {
            TangemLogger.error("📖 CARD READER VC: Failed to derive address for wallet \(index)", error: error)
        }

        let keyHex = walletInfo.wallet.publicKey.map { String(format: "%02x", $0) }.joined()
        addDetailRow(label: "Public Key", value: "0x\(keyHex)", to: walletStack)
        addDetailRow(label: "Curve", value: walletInfo.wallet.curve.rawValue, to: walletStack)
        addDetailRow(label: "Index", value: "\(walletInfo.wallet.index)", to: walletStack)
        
        if let totalSigned = walletInfo.totalSignedHashes {
            addDetailRow(label: "Total Signed Hashes", value: "\(totalSigned)", to: walletStack)
        }
        if let remaining = walletInfo.remainingSignatures {
            addDetailRow(label: "Remaining Signatures", value: "\(remaining)", to: walletStack)
        }
        
        addDetailRow(label: "Is Imported", value: walletInfo.isImported ? "Yes" : "No", to: walletStack)
        addDetailRow(label: "Has Backup", value: walletInfo.hasBackup ? "Yes" : "No", to: walletStack)
        addDetailRow(label: "Is Permanent", value: walletInfo.isPermanent ? "Yes" : "No", to: walletStack)
        
        if walletInfo.derivedKeysCount > 0 {
            addDetailRow(label: "Derived Keys", value: "\(walletInfo.derivedKeysCount)", to: walletStack)
        }
        
        stack.addArrangedSubview(walletStack)
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

