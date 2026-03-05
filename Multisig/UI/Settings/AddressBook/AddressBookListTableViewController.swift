//
//  AddressbookListTableViewController.swift
//  Multisig
//
//  Created by Moaaz on 10/20/21.
//  Copyright © 2021 Gnosis Ltd. All rights reserved.
//

import UIKit
import MobileCoreServices

class AddressBookListTableViewController: LoadableViewController, UITableViewDelegate, UITableViewDataSource {
    private var entries: [AddressBookEntry] = []
    private var menuButton: UIBarButtonItem!
    override var isEmpty: Bool {
        entries.isEmpty
    }

    var filterByChain: Chain?
    var isPickerModeEnabled: Bool = false
    var onSelect: (Address) -> Void = { _ in }

    convenience init() {
        self.init(namedClass: LoadableViewController.self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("ui_settings_address_book_title", comment: "Settings title for address book")

        tableView.delegate = self
        tableView.dataSource = self

        tableView.registerCell(DetailAccountCell.self)

        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 48

        emptyView.setTitle(NSLocalizedString("ui_address_book_empty_title", comment: "Address book empty title"))
        emptyView.setImage(UIImage(named: "ico-no-address-book")!)

        if !isPickerModeEnabled {
            menuButton = UIBarButtonItem(image: UIImage.init(systemName: "chevron.down.circle"),
                                         style: UIBarButtonItem.Style.plain,
                                         target: self,
                                         action: #selector(showOptionsMenu))
            navigationItem.rightBarButtonItem = menuButton
        }

        for notification in [Notification.Name.selectedSafeChanged, .addressbookChanged] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(reloadData), name: notification, object: nil)
        }

        reloadData()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Tracker.trackEvent(.addressBookList)
    }

    @objc private func showOptionsMenu() {
        let alertController = UIAlertController(
            title: nil,
            message: nil,
            preferredStyle: .multiplatformActionSheet)

        if let popoverPresentationController = alertController.popoverPresentationController {
            popoverPresentationController.barButtonItem = menuButton
        }

        let addEntityButton = UIAlertAction(title: "Add new entry", style: .default) { _ in
            self.didTapAddButton()
        }

        alertController.addAction(addEntityButton)

        let importEntryButton = UIAlertAction(title: "Import entries", style: .default) { [unowned self] _ in
            let pricker = UIDocumentPickerViewController(documentTypes: [String(kUTTypeCommaSeparatedText)], in: .import)
            pricker.delegate = self
            pricker.allowsMultipleSelection = false
            self.present(pricker, animated: true, completion: nil)
        }

        alertController.addAction(importEntryButton)

        if let csv = AddressBookEntry.exportToCSV() {
            let exportEntryButton = UIAlertAction(title: "Export entries", style: .default) { [unowned self] _ in
                if let exportedFileURL = FileManagerWrapper.export(text: csv,
                                                                   fileName: "AddressBook",
                                                                   fileExtension: "csv") {
                    
                    let activityViewController : UIActivityViewController = UIActivityViewController(
                        activityItems: [exportedFileURL], applicationActivities: nil)
                    activityViewController.completionWithItemsHandler = {(_ , completed, _, _) in
                        if completed {
                            Tracker.trackEvent(.addressBookExported)
                            App.shared.snackbar.show(message: NSLocalizedString("ui_address_book_exported_message", comment: "Address book exported message"))
                        }
                    }
                    self.present(activityViewController, animated: true, completion: nil)
                }
            }

            alertController.addAction(exportEntryButton)
        }

        let cancelButton = UIAlertAction(title: NSLocalizedString("cancel", comment: "Cancel action title"),
                                          style: .cancel,
                                          handler: nil)
        alertController.addAction(cancelButton)

        self.present(alertController, animated: true)
    }

    private func didTapAddButton() {
        guard let defaultChain = SCGModels.Chain.createFromCurrentChain() else { return }
        let vc = CreateAddressBookEntryViewController()
        vc.chain = defaultChain
        let ribbon = RibbonViewController(rootViewController: vc)
        ribbon.chain = vc.chain
        vc.completion = { [unowned self] (address, name) in
            AddressBookEntry.addOrUpdateAllSupportedChains(address.checksummed, name: name)
            navigationController?.popToViewController(self, animated: true)
            App.shared.snackbar.show(message: NSLocalizedString("ui_address_book_added_message", comment: "Address book added message"))
        }
        show(ribbon, sender: self)
    }
    
    @objc override func reloadData() {
        var unique = AddressBookEntry.uniqueEntries()
        if let filterByChain = filterByChain {
            unique = unique.filter { $0.chain == filterByChain }
        }
        entries = unique
        tableView.reloadData()
        onSuccess()
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        entries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueCell(DetailAccountCell.self)
        let entry = entries[indexPath.row]
        let displayChain = (try? Safe.getSelected()?.chain) ?? entry.chain!

        cell.setAccount(address: entry.addressValue,
                        label: entry.name,
                        copyEnabled: false,
                        browseURL: displayChain.browserURL(address: entry.displayAddress),
                        prefix: displayChain.shortName)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let entry = entries[indexPath.row]
        if isPickerModeEnabled {
            onSelect(entry.addressValue)
        } else {
            showEdit(entry: entry)
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !isPickerModeEnabled else { return nil }
        let entry = entries[indexPath.row]

        var actions = [UIContextualAction]()
        let editAction = UIContextualAction(style: .normal,
                                            title: NSLocalizedString("button_edit", comment: "Edit action title")) { [weak self] _, _, completion in
            self?.showEdit(entry: entry)
            completion(true)
        }
        actions.append(editAction)

        let deleteAction = UIContextualAction(style: .destructive,
                                              title: NSLocalizedString("button_delete", comment: "Delete action title")) { [weak self] _, _, completion in
            self?.remove(entry, sourceIndexPath: indexPath)
            completion(true)
        }
        actions.append(deleteAction)

        return UISwipeActionsConfiguration(actions: actions)
    }

    private func showEdit(entry: AddressBookEntry) {
        let defaultName = entry.name
        let entryAddress = entry.displayAddress

        let enterNameVC = EnterAddressNameViewController()
        enterNameVC.actionTitle = "Save"
        enterNameVC.descriptionText = "Choose a name for the entry. The name is only stored locally and will not be shared with us or any third parties."
        enterNameVC.screenTitle = "Enter entry Name"
        enterNameVC.trackingEvent = .addressBookEditEntry
        enterNameVC.placeholder = "Enter name"
        enterNameVC.name = defaultName
        enterNameVC.address = entry.addressValue
        enterNameVC.prefix = (try? Safe.getSelected()?.chain)?.shortName
        enterNameVC.completion = { [unowned self] name in
            AddressBookEntry.updateAllChains(entryAddress, name: name)
            navigationController?.popViewController(animated: true)
            App.shared.snackbar.show(message: NSLocalizedString("ui_address_book_updated_message", comment: "Address book updated message"))
        }
        
        let ribbonVC = RibbonViewController(rootViewController: enterNameVC)

        show(ribbonVC, sender: nil)
    }

    private func remove(_ entry: AddressBookEntry, sourceIndexPath: IndexPath) {
        let entryAddress = entry.displayAddress
        let alertController = UIAlertController(
            title: nil,
            message: "Removing the entry key only removes it from this app.",
            preferredStyle: .multiplatformActionSheet)

        let remove = UIAlertAction(title: "Remove", style: .destructive) { _ in
            AddressBookEntry.removeFromAllChains(entryAddress)
            App.shared.snackbar.show(message: NSLocalizedString("ui_address_book_removed_message", comment: "Address book removed message"))
        }
        let cancel = UIAlertAction(title: NSLocalizedString("cancel", comment: "Cancel action title"),
                                   style: .cancel,
                                   handler: nil)
        alertController.addAction(remove)
        alertController.addAction(cancel)
        
        if let popoverPresentationController = alertController.popoverPresentationController {
            popoverPresentationController.sourceView = tableView
            popoverPresentationController.sourceRect = tableView.rectForRow(at: sourceIndexPath)
        }
        
        present(alertController, animated: true)
    }
}

extension AddressBookListTableViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        if let csv = FileManagerWrapper.importFile(url: url) {
            let result = AddressBookEntry.importFrom(csv: csv)
            Tracker.trackEvent(.addressBookImported)
            App.shared.snackbar.show(message: String(format: NSLocalizedString("ui_address_book_imported_updated_format",
                                                                              comment: "Address book imported/updated format"),
                                                     result.0,
                                                     result.1))
        }
    }
}
