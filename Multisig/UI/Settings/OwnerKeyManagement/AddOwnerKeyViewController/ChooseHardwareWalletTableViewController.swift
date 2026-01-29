//
//  ChooseHardwareWalletTableViewController.swift
//  Multisig
//
//  Created by Mouaz on 9/7/23.
//  Copyright © 2023 Gnosis Ltd. All rights reserved.
//

import UIKit

class ChooseHardwareWalletTableViewController: UITableViewController {
    private typealias SectionItems = (section: String, items: [Row])

    enum Row {
        case cardKey
        case ledger
        case keystone
        case tangem
        case tangem0
        case burner

        var title: String {
            switch self {
            case .cardKey:
                return NSLocalizedString("ui_card_key_connect_title", comment: "Title for connecting a card key")
            case .ledger:
                return NSLocalizedString("ui_ledger_connect_nano_x_title", comment: "Title for connecting a Ledger Nano X device")
            case .keystone:
                return NSLocalizedString("ui_keystone_connect_title", comment: "Title for connecting a Keystone device")
            case .tangem:
                return NSLocalizedString("ui_tangem_connect_card_title", comment: "Title for connecting a Tangem card")
            case .tangem0:
                return NSLocalizedString("ui_tangem0_connect_card_title", comment: "Title for connecting a Tangem0 card")
            case .burner:
                return NSLocalizedString("ui_burner_connect_card_title", comment: "Title for the burner owner key connect flow")
            }
        }

        var image: UIImage {
            switch self {
            case .cardKey:
                return UIImage(named: "ico-payment-key")!
            case .keystone:
                return UIImage(named: KeyType.keystone.imageName)!
            case .ledger:
                return UIImage(named: KeyType.ledgerNanoX.imageName)!
            case .tangem:
                return UIImage(named: KeyType.tangem.imageName)!
            case .tangem0:
                return UIImage(named: KeyType.tangem0.imageName)!
            case .burner:
                return UIImage(named: KeyType.burner.imageName)!
            }
        }
    }

    private var sections = [SectionItems]()
    var completion: () -> Void = {}

    private var connectKeystoneFlow: ConnectKeystoneFlow!
    private var ledgerKeyFlow: LedgerKeyFlow!
    private var tangemKeyFlow: TangemKeyFlow!
    private var tangem0KeyFlow: TangemKeyFlow!
    private var burnerKeyFlow: BurnerKeyFlow!
    private var cardKeyFlow: AddKeyFlow?
    private var tangemProvisioningCoordinator: TangemCardKeyProvisioningCoordinator?

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("ui_hardware_pair_device_title", comment: "Title for selecting/pairing a hardware device")

        tableView.registerCell(AddOwnerKeyCell.self)
        tableView.separatorStyle = .none
        tableView.estimatedRowHeight = 90
        tableView.rowHeight = UITableView.automaticDimension
        tableView.backgroundColor = .backgroundSecondary
        tableView.tableFooterView = UIView()

        // Only show Ledger and Keystone
        sections = [
            (section: "", items: [.ledger, .keystone])
        ]
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Tracker.trackEvent(.chooseHardwareWallet)
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].items.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueCell(AddOwnerKeyCell.self)
        let option = sections[indexPath.section].items[indexPath.row]

        cell.set(title: option.title)
        cell.set(image: option.image)
        cell.set(style: .normal)
        cell.set(detailsImage: nil)

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch sections[indexPath.section].items[indexPath.row] {
        case .cardKey:
            // Route by cached lead manufacturer.
            let manufacturer = (AppSettings.leadCardManufacturer ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if manufacturer == "tangem" {
                startTangemCardKeyFlow()
            } else if manufacturer == "burner" {
                startBurnerCardKeyFlow()
            } else {
                presentCardKeyManufacturerChoice()
            }

        case .ledger:
            ledgerKeyFlow = LedgerKeyFlow { [unowned self] _ in
                ledgerKeyFlow = nil
                completion()
            }
            push(flow: ledgerKeyFlow)

        case .keystone:
            connectKeystoneFlow = ConnectKeystoneFlow { [unowned self] _ in
                connectKeystoneFlow = nil
                completion()
            }
            push(flow: connectKeystoneFlow)

        case .tangem:
            let coordinator = TangemCardKeyProvisioningCoordinator(
                presentIntro: { [weak self] introVC in
                    guard let self else { return }
                    self.show(introVC, sender: self)
                },
                presentActivation: { [weak self] activationVC in
                    guard let self else { return }
                    self.show(activationVC, sender: self)
                },
                presentPostActivationIntro: { [weak self] introVC in
                    guard let self else { return }
                    self.show(introVC, sender: self)
                },
                presentImportFlow: { [weak self] flow in
                    guard let self else { return }
                    self.tangemKeyFlow = flow
                    self.cardKeyFlow = flow
                    self.push(flow: flow)
                },
                configureImportFlow: { flow in
                    flow.skipIntro = true
                },
                onImportCompletion: { [weak self] _ in
                    self?.tangemKeyFlow = nil
                    self?.cardKeyFlow = nil
                    self?.tangemProvisioningCoordinator = nil
                    self?.completion()
                }
            )
            tangemProvisioningCoordinator = coordinator
            coordinator.start()
        case .tangem0:
            tangem0KeyFlow = TangemKeyFlow(service: Tangem0Service.shared, keyType: .tangem0) { [unowned self] _ in
                tangem0KeyFlow = nil
                completion()
            }
            push(flow: tangem0KeyFlow)
        case .burner:
            burnerKeyFlow = BurnerKeyFlow { [unowned self] _ in
                burnerKeyFlow = nil
                completion()
            }
            push(flow: burnerKeyFlow)
        }
    }

    private func startTangemCardKeyFlow() {
        tangemKeyFlow = TangemKeyFlow(service: TangemService.shared) { [unowned self] _ in
            tangemKeyFlow = nil
            completion()
        }
        cardKeyFlow = tangemKeyFlow
        push(flow: tangemKeyFlow)
    }

    private func startBurnerCardKeyFlow() {
        burnerKeyFlow = BurnerKeyFlow { [unowned self] _ in
            burnerKeyFlow = nil
            completion()
        }
        cardKeyFlow = burnerKeyFlow
        push(flow: burnerKeyFlow)
    }

    private func presentCardKeyManufacturerChoice() {
        let title = NSLocalizedString("ui_card_key_connect_title", comment: "Title for connecting a card key")
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: NSLocalizedString("ui_tangem_connect_card_title", comment: "Title for connecting a Tangem card"), style: .default) { [weak self] _ in
            self?.startTangemCardKeyFlow()
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("ui_burner_connect_card_title", comment: "Title for the burner owner key connect flow"), style: .default) { [weak self] _ in
            self?.startBurnerCardKeyFlow()
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("cancel", comment: "Cancel action title"), style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        present(alert, animated: true)
    }
}
