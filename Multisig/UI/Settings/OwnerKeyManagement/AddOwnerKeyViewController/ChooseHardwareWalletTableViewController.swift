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
        case ledger
        case keystone
        case tangem
        case tangem0
        case burner

        var title: String {
            switch self {
            case .ledger:
                return "Connect Ledger Nano X"
            case .keystone:
                return "Connect Keystone"
            case .tangem:
                return "Connect Tangem Card"
            case .tangem0:
                return "Connect Tangem0 Card"
            case .burner:
                return "Connect Burner Card"
            }
        }

        var image: UIImage {
            switch self {
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

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Pair hardware device"

        tableView.registerCell(AddOwnerKeyCell.self)
        tableView.separatorStyle = .none
        tableView.estimatedRowHeight = 90
        tableView.rowHeight = UITableView.automaticDimension
        tableView.backgroundColor = .backgroundSecondary
        tableView.tableFooterView = UIView()

        var hardwareOptions: [Row] = [.ledger, .keystone, .tangem, .tangem0]
        if AppConfiguration.FeatureToggles.burnerWallet {
            hardwareOptions.append(.burner)
        }
        sections = [
            (section: "", items: hardwareOptions)
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
            tangemKeyFlow = TangemKeyFlow(service: TangemService.shared) { [unowned self] _ in
                tangemKeyFlow = nil
                completion()
            }
            push(flow: tangemKeyFlow)
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
}
