//
//  BurnerScanViewController.swift
//  Multisig
//
//  Created by GPT-5.1 Codex.
//

import UIKit
import SafeWeb3

final class BurnerScanViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var onSlotSelected: ((BurnerKeySelection) -> Void)?
    var onCancelled: (() -> Void)?
    
    /// When enabled, the scan will automatically pick the first available slot and continue the flow.
    /// This avoids prompting the user to choose a slot.
    var autoSelectFirstSlot: Bool = false
    
    /// Optional target slot to auto-select (for card-key provisioning we use slot 3).
    var targetSlot: Int?
    
    private enum State {
        case idle
        case scanning
        case ready
        case error(String)
    }
    
    private let service: BurnerService
    
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let statusLabel = UILabel()
    private let detailLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let actionButton = UIButton(type: .system)
    private let stackView = UIStackView()
    
    private var state: State = .idle {
        didSet { updateUI(for: state) }
    }
    
    private var summary: BurnerService.BurnerCardSummary?
    private var scanTask: Task<Void, Never>?
    private var hasStarted = false
    
    init(service: BurnerService) {
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
        tableView.tableFooterView = UIView()
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 24)
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 24),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func configureActionButton() {
        actionButton.setTitle(NSLocalizedString("ui_try_again", comment: "Retry button title"), for: .normal)
        actionButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        actionButton.isHidden = true
    }
    
    private func startScan(forceRefresh: Bool) {
        scanTask?.cancel()
        state = .scanning
        tableView.isHidden = true
        
        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let summary = try await self.service.scanCard(forceRefresh: forceRefresh)
                BurnerLogger.info("Burner scan succeeded. cardId=\(summary.cardId) slots=\(summary.keySlots.count)")
                await MainActor.run {
                    if summary.keySlots.isEmpty {
                        self.summary = nil
                        self.state = .error(NSLocalizedString("ui_burner_no_eth_slots_error", comment: "Error shown when Burner card doesn't have compatible key slots"))
                        self.tableView.isHidden = true
                    } else {
                        self.summary = summary
                        if self.autoSelectFirstSlot {
                            let selectedSlot: BurnerService.BurnerKeySlot?
                            if let targetSlot = self.targetSlot {
                                selectedSlot = summary.keySlots.first(where: { $0.slot == targetSlot })
                            } else {
                                selectedSlot = summary.keySlots.first
                            }
                            
                            guard let selected = selectedSlot else {
                                self.summary = nil
                                self.state = .error(
                                    String(
                                        format: NSLocalizedString("ui_burner_target_slot_missing_format", comment: "Error shown when expected Burner slot is missing"),
                                        self.targetSlot ?? -1
                                    )
                                )
                                self.tableView.isHidden = true
                                BurnerLogger.warning("Burner auto-selection failed: target slot not found target=\(self.targetSlot ?? -1) cardId=\(summary.cardId)")
                                return
                            }
                            
                            // Proceed automatically with the selected slot.
                            self.state = .scanning
                            self.tableView.isHidden = true
                            let slot1PublicKey = summary.keySlots.first(where: { $0.slot == 1 })?.publicKey
                            let selection = BurnerKeySelection(cardId: summary.cardId,
                                                               tagIdentifier: summary.tagIdentifier,
                                                               slot: selected.slot,
                                                               publicKey: selected.publicKey,
                                                               slot1PublicKey: slot1PublicKey,
                                                               address: selected.ethereumAddress,
                                                               attestationValid: selected.attestationValid)
                            BurnerLogger.info("Burner auto-selected slot cardId=\(summary.cardId) slot=\(selected.slot)")
                            self.onSlotSelected?(selection)
                        } else {
                            self.state = .ready
                            self.tableView.reloadData()
                            self.tableView.isHidden = false
                        }
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                let message = self.message(for: error)
                BurnerLogger.error("Burner scan failed", error: error)
                await MainActor.run {
                    self.state = .error(message)
                }
            }
        }
    }
    
    private func message(for error: Error) -> String {
        if let burnerError = error as? BurnerService.BurnerServiceError {
            return burnerError.errorDescription ?? NSLocalizedString("ui_burner_unable_to_scan_fallback", comment: "Fallback error for Burner scan failure")
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
        case .scanning:
            statusLabel.text = NSLocalizedString("ui_tangem_scanning_title", comment: "Status shown while scanning Tangem card")
            detailLabel.text = NSLocalizedString("ui_tangem_hold_near_top_edge", comment: "Instruction for holding Tangem card near phone")
            activityIndicator.startAnimating()
            actionButton.isHidden = true
        case .ready:
            statusLabel.text = NSLocalizedString("ui_burner_select_key_slot_title", comment: "Title shown when selecting a Burner key slot")
            if let summary = summary {
                detailLabel.text = String(
                    format: NSLocalizedString("ui_burner_detected_card_choose_slot_format", comment: "Detail shown after detecting a Burner card; includes card id"),
                    summary.cardId
                )
            } else {
                detailLabel.text = NSLocalizedString("ui_burner_choose_slot_detail", comment: "Detail shown when asking user to choose a key slot")
            }
            activityIndicator.stopAnimating()
            actionButton.isHidden = true
        case .error(let message):
            statusLabel.text = NSLocalizedString("ui_burner_unable_to_scan_title", comment: "Title shown when Burner scan fails")
            detailLabel.text = message
            activityIndicator.stopAnimating()
            actionButton.isHidden = false
        }
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
        summary?.keySlots.count ?? 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let reuseIdentifier = "BurnerSlotCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseIdentifier) ??
            UITableViewCell(style: .subtitle, reuseIdentifier: reuseIdentifier)
        guard let slot = summary?.keySlots[indexPath.row] else { return cell }
        cell.textLabel?.text = slot.ethereumAddress.checksummed
        cell.detailTextLabel?.text = String(
            format: NSLocalizedString("ui_burner_slot_format", comment: "Burner slot label, e.g. 'Slot #1'"),
            slot.slot
        )
        cell.imageView?.image = UIImage(named: KeyType.burner.imageName)
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
        return cell
    }
    
    // MARK: - UITableViewDelegate
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let summary = summary else { return }
        let slot = summary.keySlots[indexPath.row]
        let slot1PublicKey = summary.keySlots.first(where: { $0.slot == 1 })?.publicKey
        let selection = BurnerKeySelection(cardId: summary.cardId,
                                           tagIdentifier: summary.tagIdentifier,
                                           slot: slot.slot,
                                           publicKey: slot.publicKey,
                                           slot1PublicKey: slot1PublicKey,
                                           address: slot.ethereumAddress,
                                           attestationValid: slot.attestationValid)
        BurnerLogger.info("Burner slot selected cardId=\(summary.cardId) slot=\(slot.slot)")
        onSlotSelected?(selection)
    }
}

