//
//  ChangeDisplayModeTableViewController.swift
//  Multisig
//
//  Created by Moaaz on 2/6/21.
//  Copyright © 2021 Gnosis Ltd. All rights reserved.
//

import UIKit

class ChangeDisplayModeTableViewController: UITableViewController {
    private let items: [(name: String, style: UIUserInterfaceStyle)] = [
        (NSLocalizedString("ui_settings_display_auto", comment: "Appearance mode auto"), UIUserInterfaceStyle.unspecified),
        (NSLocalizedString("ui_settings_display_light", comment: "Appearance mode light"), UIUserInterfaceStyle.light),
        (NSLocalizedString("ui_settings_display_dark", comment: "Appearance mode dark"), UIUserInterfaceStyle.dark)
    ]

    private var selectedDisplayMode: UIUserInterfaceStyle {
        get {
            App.shared.theme.displayMode
        }
        set {
            App.shared.theme.displayMode = newValue
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = NSLocalizedString("ui_settings_appearance_title", comment: "Settings title for appearance")

        tableView.registerCell(BasicCell.self)
        tableView.rowHeight = BasicCell.rowHeight

        tableView.backgroundColor = .backgroundSecondary
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Tracker.trackEvent(.settingsAppAppearance)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let disclosureImage = items[indexPath.row].style == selectedDisplayMode ?
            UIImage(systemName: "checkmark")?.withTintColor(.primary) : nil
        let cell = tableView.basicCell(
            name: "\(items[indexPath.row].name)",
            icon: nil,
            indexPath: indexPath,
            disclosureImage: disclosureImage
        )
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selectedDisplayMode = items[indexPath.row].style
        tableView.reloadData()
    }
}
