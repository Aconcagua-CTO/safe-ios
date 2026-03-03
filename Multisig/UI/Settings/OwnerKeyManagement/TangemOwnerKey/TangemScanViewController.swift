import UIKit
import TangemSdk

final class TangemScanViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var onWalletSelected: ((TangemWalletSelection) -> Void)?
    var onCancelled: (() -> Void)?
    var autoSelectFirstWallet: Bool = false

    private enum State {
        case idle
        case scanning
        case ready
        case error(String)
    }

    private struct WalletItem {
        let wallet: TangemCardSummary.Wallet
        let rawPublicKey: Data
        let normalizedPublicKey: Data
        let address: Address
    }

    private let service: TangemCardService

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let statusLabel = UILabel()
    private let detailLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let actionButton = UIButton(type: .system)
    private let stackView = UIStackView()

    private var state: State = .idle {
        didSet { updateUI(for: state) }
    }

    private var walletItems: [WalletItem] = []
    private var cardId: String?
    private var scanTask: Task<Void, Never>?
    private var hasStarted = false
    private var hasAutoSelected = false

    init(service: TangemCardService) {
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

        view.backgroundColor = .backgroundSecondary
        navigationItem.title = NSLocalizedString("ui_tangem_scan_card_title", comment: "Title for scanning a Tangem card")
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel,
                                                            target: self,
                                                            action: #selector(cancelTapped))

        configureStackView()
        configureTableView()
        configureActionButton()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasStarted else { return }
        hasStarted = true
        startScan(forceRefresh: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        scanTask?.cancel()
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
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }

    private func configureTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.rowHeight = 72
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 24)
        tableView.tableFooterView = UIView()
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 24),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureActionButton() {
        actionButton.setTitle(NSLocalizedString("button_retry", comment: "Retry button title"), for: .normal)
        actionButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        actionButton.isHidden = true
    }

    private func startScan(forceRefresh: Bool) {
        scanTask?.cancel()
        walletItems = []
        tableView.reloadData()
        state = .scanning

        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let message = Message(
                    header: nil,
                    body: NSLocalizedString("ui_tangem_scan_message_body", comment: "Tangem scan message body")
                )

                let summary = try await self.service.scanCard(forceRefresh: forceRefresh, initialMessage: message)
                let supportedWallets = summary.wallets.filter { $0.curve == .secp256k1 }
                let items: [WalletItem] = try supportedWallets.map { wallet in
                    let normalizedKey = try self.service.normalizedWalletPublicKey(wallet.publicKey)
                    let address = try self.service.ethereumAddress(fromNormalizedPublicKey: normalizedKey)
                    let logLine = "Tangem scan wallet index=\(wallet.index) rawKey(\(wallet.publicKey.count) bytes)=\(wallet.publicKey.tangemHexDescription()) normalizedKey(\(normalizedKey.count) bytes)=\(normalizedKey.tangemHexDescription()) address=\(address.checksummed)"
                    LogService.shared.info("[TangemScan] \(logLine)")
                    print("[TangemScan] \(logLine)")
                    NSLog("[TangemScan] %@", logLine)
                    return WalletItem(wallet: wallet,
                                      rawPublicKey: wallet.publicKey,
                                      normalizedPublicKey: normalizedKey,
                                      address: address)
                }

                guard !items.isEmpty else {
                    throw TangemServiceError.missingWallet
                }

                await MainActor.run {
                    self.cardId = summary.cardId
                    self.walletItems = items
                    if self.autoSelectFirstWallet {
                        self.autoSelectFirstWalletIfNeeded()
                    } else {
                        self.state = .ready
                        self.tableView.reloadData()
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                let message = self.message(for: error)
                TangemLogger.error("Tangem scan failed", error: error)
                await MainActor.run {
                    self.state = .error(message)
                }
            }
        }
    }

    private func updateUI(for state: State) {
        switch state {
        case .idle:
            statusLabel.text = nil
            detailLabel.text = nil
            activityIndicator.stopAnimating()
            actionButton.isHidden = true
            tableView.isHidden = true

        case .scanning:
            statusLabel.text = NSLocalizedString("ui_tangem_scanning_title", comment: "Status shown while scanning Tangem card")
            detailLabel.text = NSLocalizedString("ui_tangem_hold_near_top_edge", comment: "Instruction for holding Tangem card near phone")
            activityIndicator.startAnimating()
            actionButton.isHidden = true
            tableView.isHidden = true

        case .ready:
            statusLabel.text = NSLocalizedString("ui_tangem_select_wallet_title", comment: "Title shown when selecting a Tangem wallet")
            detailLabel.text = NSLocalizedString("ui_tangem_choose_wallet_detail", comment: "Detail shown when choosing a Tangem wallet")
            activityIndicator.stopAnimating()
            actionButton.isHidden = true
            tableView.isHidden = false

        case .error(let message):
            statusLabel.text = NSLocalizedString("ui_tangem_unable_to_scan_title", comment: "Title shown when Tangem scan fails")
            detailLabel.text = message
            activityIndicator.stopAnimating()
            actionButton.isHidden = false
            tableView.isHidden = true
        }
    }

    private func message(for error: Error) -> String {
        if let tangemError = error as? TangemServiceError {
            switch tangemError {
            case .nfcUnavailable:
                return NSLocalizedString("ui_tangem_error_nfc_unavailable", comment: "Error when NFC is unavailable for Tangem")
            case .userCancelled:
                return NSLocalizedString("ui_tangem_error_user_cancelled", comment: "Error when Tangem scan is cancelled")
            case .missingWallet:
                return NSLocalizedString("ui_tangem_error_missing_wallet", comment: "Error when Tangem card has no Ethereum-compatible wallet")
            case .cardMismatch(let expected, let actual):
                return String(format: NSLocalizedString("ui_tangem_error_card_mismatch_format", comment: "Error when Tangem card does not match expected"), expected, actual)
            case .invalidDerivationPath(let path):
                return String(format: NSLocalizedString("ui_tangem_error_invalid_derivation_path_format", comment: "Error when Tangem derivation path is unsupported"), path)
            case .unsupportedCurve:
                return NSLocalizedString("ui_tangem_error_unsupported_curve", comment: "Error when Tangem wallet is incompatible")
            case .sdkError(let sdkError):
                return sdkError.localizedDescription
            case .underlying(let underlying):
                return underlying.localizedDescription
            }
        }

        return error.localizedDescription
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        onCancelled?()
    }

    @objc private func retryTapped() {
        startScan(forceRefresh: true)
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        walletItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let reuseIdentifier = "TangemWalletCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseIdentifier) ?? UITableViewCell(style: .subtitle, reuseIdentifier: reuseIdentifier)
        let item = walletItems[indexPath.row]
        cell.textLabel?.text = item.address.checksummed
        cell.detailTextLabel?.text = String(
            format: NSLocalizedString("ui_tangem_wallet_format", comment: "Tangem wallet label format"),
            item.wallet.index
        )
        cell.imageView?.image = UIImage(named: KeyType.tangem.imageName)
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
        return cell
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let cardId = cardId else { return }
        let item = walletItems[indexPath.row]
        selectWallet(item, cardId: cardId, allowDebugAlert: true)
    }

    private func autoSelectFirstWalletIfNeeded() {
        guard autoSelectFirstWallet, !hasAutoSelected else { return }
        guard let cardId = cardId, let first = walletItems.first else {
            state = .ready
            tableView.reloadData()
            return
        }
        hasAutoSelected = true
        selectWallet(first, cardId: cardId, allowDebugAlert: false)
    }

    private func selectWallet(_ item: WalletItem, cardId: String, allowDebugAlert: Bool) {
        let derivationPath = TangemDerivationPathPolicy.defaultDerivationPath(for: item.wallet)
        let selection = TangemWalletSelection(cardId: cardId,
                                              walletPublicKey: item.rawPublicKey,
                                              address: item.address,
                                              derivationPath: derivationPath,
                                              walletIndex: item.wallet.index)
        let pathLog = derivationPath ?? "nil"
        TangemLogger.debug("Derived default path for wallet index \(item.wallet.index): \(pathLog)")
        TangemLogger.info("User selected Tangem wallet index=\(item.wallet.index) cardId=\(cardId)")
        #if DEBUG
        if allowDebugAlert {
            let rawKeyHex = item.rawPublicKey.tangemHexDescription(prefix: true)
            let message = """
            Address: \(item.address.checksummed)
            Wallet index: \(item.wallet.index)
            Public key: \(rawKeyHex)
            """
            let alert = UIAlertController(title: NSLocalizedString("ui_tangem_wallet_key_title", comment: "Tangem wallet key alert title"),
                                          message: message,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("ui_walletconnect_copy_continue_title", comment: "Copy and continue button title"),
                                          style: .default) { [weak self] _ in
                UIPasteboard.general.string = rawKeyHex
                self?.onWalletSelected?(selection)
            })
            alert.addAction(UIAlertAction(title: NSLocalizedString("cancel", comment: "Cancel action title"),
                                          style: .cancel))
            present(alert, animated: true)
            return
        }
        #endif
        onWalletSelected?(selection)
    }
}

