//
//  ChainSettingsTableViewController.swift
//  Multisig
//
//  Created by Moaaz on 11/4/21.
//  Copyright © 2021 Gnosis Ltd. All rights reserved.
//

import UIKit

class ChainSettingsTableViewController: UITableViewController {

    fileprivate struct Section {
        let title: String
        let items: [Row]
    }

    enum Row: Int, CaseIterable {
        case copyAddressWithChainPrefix
        case prependChainPrefixToAddresses
        case copyAddressWithChainPrefixHelp
        case prependChainPrefixToAddressesHelp
    }

    private var sections: [Section] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = NSLocalizedString("ui_settings_chain_prefix_title", comment: "Settings title for chain prefix")

        tableView.registerCell(SwitchTableViewCell.self)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "HelpCell")

        tableView.backgroundColor = .backgroundSecondary
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        sections.append(Section(title: NSLocalizedString("ui_settings_chain_prefix_section_title", comment: "Chain prefix section title"),
                                items: [.prependChainPrefixToAddresses,
                                                                 .prependChainPrefixToAddressesHelp,
                                                                 .copyAddressWithChainPrefix,
                                                                 .copyAddressWithChainPrefixHelp]))
        tableView.reloadData()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Tracker.trackEvent(.settingsAppChainPrefix)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].items.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch sections[indexPath.section].items[indexPath.row] {
        case .copyAddressWithChainPrefix:
            return tableView.switchCell(for: indexPath,
                                        with: NSLocalizedString("ui_settings_chain_copy_prefix_title", comment: "Chain prefix setting title"),
                                        isOn: AppSettings.copyAddressWithChainPrefix)
        case .copyAddressWithChainPrefixHelp:
            return tableView.helpCell(for: indexPath,
                                      with: NSLocalizedString("ui_settings_chain_copy_prefix_help", comment: "Chain prefix setting help"))

        case .prependChainPrefixToAddresses:
            return tableView.switchCell(for: indexPath,
                                        with: NSLocalizedString("ui_settings_chain_prepend_prefix_title", comment: "Chain prefix setting title"),
                                        isOn: AppSettings.prependingChainPrefixToAddresses)

        case .prependChainPrefixToAddressesHelp:
            return tableView.helpCell(for: indexPath,
                                      with: NSLocalizedString("ui_settings_chain_prepend_prefix_help", comment: "Chain prefix setting help"))
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = sections[indexPath.section].items[indexPath.row]
        switch item {
        case .copyAddressWithChainPrefix:
            AppSettings.copyAddressWithChainPrefix.toggle()
            tableView.reloadData()
        case .prependChainPrefixToAddresses:
            AppSettings.prependingChainPrefixToAddresses.toggle()
            tableView.reloadData()
        default:
            break
        }

        NotificationCenter.default.post(name: .chainSettingsChanged, object: self)
    }
}
