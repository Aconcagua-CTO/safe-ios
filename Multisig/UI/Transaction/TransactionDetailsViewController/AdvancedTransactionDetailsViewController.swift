//
//  AdvancedTransactionDetailsViewController.swift
//  Multisig
//
//  Created by Moaaz on 9/29/21.
//  Copyright © 2021 Gnosis Ltd. All rights reserved.
//

import UIKit

class AdvancedTransactionDetailsViewController: UITableViewController {
    private var sections: [Section] = []
    private var chain: Chain!

    var trackingEvent: TrackingEvent = .transactionsDetailsAdvanced

    convenience init(_ tx: SCGModels.TransactionDetails, chain: Chain) {
        self.init()
        self.chain = chain
        buildSections(tx)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Tracker.trackEvent(trackingEvent)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = NSLocalizedString("ui_tx_advanced_title", comment: "Title for advanced transaction details screen")

        tableView.registerCell(DetailAccountCell.self)
        tableView.registerCell(DetailExpandableTextCell.self)
        tableView.registerCell(DetailDisclosingCell.self)
        tableView.registerHeaderFooterView(BasicHeaderView.self)

        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        } else {
            // Fallback on earlier versions
        }
        tableView.estimatedSectionHeaderHeight = BasicHeaderView.headerHeight
        tableView.estimatedSectionFooterHeight = 0

        for notification in [Notification.Name.ownerKeyImported,
                             .ownerKeyRemoved,
                             .ownerKeyUpdated,
                             .addressbookChanged,
                             .selectedSafeChanged,
                             .selectedSafeUpdated] {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(lazyReloadData),
                name: notification,
                object: nil)
        }
    }

    func buildSections(_ tx: SCGModels.TransactionDetails) {
        if let hash = tx.txHash?.description {
            sections.append(Section(title: NSLocalizedString("ui_tx_chain_transaction_data_title", comment: "Chain transaction data section title"),
                                    items: [SectionItem(title: NSLocalizedString("ui_tx_transaction_hash_title", comment: "Transaction hash title"),
                                                        value: hash)]))
        }

        if let txData = tx.txData {
            var safeTransactionData: [SectionItem] = []
            safeTransactionData.append(SectionItem(title: NSLocalizedString("ui_tx_to_title", comment: "Transaction to title"),
                                                   value: txData.to))
            safeTransactionData.append(SectionItem(title: NSLocalizedString("ui_tx_value_title", comment: "Transaction value title"),
                                                   value: txData.value.description))

            if let dataDecoded = txData.dataDecoded {
                let addressInfoIndex = txData.addressInfoIndex
                if dataDecoded.method == "multiSend",
                   let param = dataDecoded.parameters?.first,
                   param.type == "bytes",
                   case let SCGModels.DataDecoded.Parameter.ValueDecoded.multiSend(multiSendTxs)? = param.valueDecoded {
                    safeTransactionData.append(SectionItem(title: String(format: NSLocalizedString("ui_tx_multisend_actions_title_format", comment: "Multisend actions title"),
                                                                         multiSendTxs.count),
                                                           value: (multiSendTxs, addressInfoIndex)))
                } else {
                    safeTransactionData.append(SectionItem(title: String(format: NSLocalizedString("ui_tx_action_method_title_format", comment: "Action title with method"),
                                                                         dataDecoded.method),
                                                           value: (dataDecoded, addressInfoIndex, tx.txData?.hexData)))
                }
            }

            if let data = txData.hexData {
                safeTransactionData.append(SectionItem(title: NSLocalizedString("ui_tx_data_title", comment: "Transaction data title"),
                                                       value: data))
            }

            safeTransactionData.append(SectionItem(title: NSLocalizedString("ui_tx_operation_title", comment: "Transaction operation title"),
                                                   value: "\(txData.operation.rawValue) (\(txData.operation.name))"))

            sections.append(Section(title: NSLocalizedString("ui_tx_safe_account_transaction_data_title", comment: "Safe account transaction data title"),
                                    items: safeTransactionData))
        }

        if case SCGModels.TransactionDetails.DetailedExecutionInfo.multisig(let multisigTx)? =
            tx.detailedExecutionInfo {
            sections.append(Section(title: "",
                                    items: [SectionItem(title: NSLocalizedString("ui_tx_safe_tx_hash_title", comment: "safeTxHash title"),
                                                        value: multisigTx.safeTxHash.description),
                                            SectionItem(title: NSLocalizedString("ui_tx_nonce_title_label", comment: "Nonce title"),
                                                        value: multisigTx.nonce.description)]))
        }

        switch tx.detailedExecutionInfo {
        case .multisig(let multisigInfo):
            var multiSigTransactionInfo: [SectionItem] = []
            multiSigTransactionInfo.append(SectionItem(title: NSLocalizedString("ui_tx_safe_tx_gas_title", comment: "safeTxGas title"),
                                                       value: multisigInfo.safeTxGas.description))
            multiSigTransactionInfo.append(SectionItem(title: NSLocalizedString("ui_tx_base_gas_title", comment: "baseGas title"),
                                                       value: multisigInfo.baseGas.description))
            multiSigTransactionInfo.append(SectionItem(title: NSLocalizedString("ui_tx_gas_price_title", comment: "gasPrice title"),
                                                       value: multisigInfo.gasPrice.description))
            multiSigTransactionInfo.append(SectionItem(title: NSLocalizedString("ui_tx_gas_token_title", comment: "gasToken title"),
                                                       value: multisigInfo.gasToken.address.addressInfo))
            multiSigTransactionInfo.append(SectionItem(title: NSLocalizedString("ui_tx_refund_receiver_title", comment: "refundReceiver title"),
                                                       value: multisigInfo.refundReceiver))

            sections.append(Section(title: NSLocalizedString("ui_tx_multisig_data_title", comment: "Multisig data section title"),
                                    items: multiSigTransactionInfo))

            var signatures: [SectionItem] = []
            multisigInfo.confirmations.forEach { confirmation in
                signatures.append(SectionItem(title: nil, value: confirmation.signature))
            }

            sections.append(Section(title: NSLocalizedString("ui_tx_signatures_title", comment: "Signatures section title"),
                                    items: signatures))
        case .module(let moduleInfo):
            sections.append(Section(title: NSLocalizedString("ui_tx_module_data_title", comment: "Module data section title"),
                                    items: [SectionItem(title: NSLocalizedString("ui_tx_module_address_title", comment: "Module address title"),
                                                        value: moduleInfo.address)]))
        default:
            break
        }

        sections = sections.filter { section in !section.items.isEmpty }
    }

    @objc func lazyReloadData() {
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        BasicHeaderView.headerHeight
    }

    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        0
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].items.count
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let section = sections[section]
        let view = tableView.dequeueHeaderFooterView(BasicHeaderView.self)
        view.setName(section.title)
        return view
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = sections[indexPath.section].items[indexPath.row]
        if let addressInfo = item.value as? SCGModels.AddressInfo {
            let info = addressInfo.addressInfo
            let (name, _) = NamingPolicy.name(for: info.address, info: info, chainId: chain.id!)
            return address(addressInfo.value.address,
                           label: name,
                           title: item.title,
                           imageUri: addressInfo.logoUri,
                           indexPath: indexPath,
                           browseURL: chain.browserURL(address: addressInfo.value.description),
                           prefix: chain.shortName)
        } else if let addressInfo = item.value as? AddressInfo {
            let (name, _) = NamingPolicy.name(for: addressInfo.address, info: addressInfo, chainId: chain.id!)
            return address(addressInfo.address,
                           label: name,
                           title: item.title,
                           imageUri: addressInfo.logoUri,
                           indexPath: indexPath,
                           browseURL: chain.browserURL(address: addressInfo.address.checksummed),
                           prefix: chain.shortName)
        }
        else if let string = item.value as? String {
            return text(string, title: item.title, expandableTitle: nil, copyText: string, indexPath: indexPath)
        } else if let data = item.value as? DataString {
            return text("\(data)", title: item.title,
                        expandableTitle: String(format: NSLocalizedString("ui_tx_bytes_title_format", comment: "Bytes count title"),
                                                "\(data.data.count)"),
                        copyText: "\(data)",
                        indexPath: indexPath)
        } else if let multiSendDataDecoded = item.value as? ([SCGModels.DataDecoded.Parameter.ValueDecoded.MultiSendTx],
                                                             SCGModels.AddressInfoIndex?) {
            return disclosure(text: item.title ?? "", indexPath: indexPath) { [weak self] in
                guard let `self` = self else { return }
                let root = MultiSendListTableViewController(transactions: multiSendDataDecoded.0,
                                                            addressInfoIndex: multiSendDataDecoded.1,
                                                            chain: self.chain)
                 let vc = RibbonViewController(rootViewController: root)
                self.show(vc, sender: self)
             }
        } else if let actionDataDecoded = item.value as? (SCGModels.DataDecoded,
                                                          SCGModels.AddressInfoIndex?, DataString?) {
            return disclosure(text: item.title ?? "", indexPath: indexPath) { [weak self] in
                guard let `self` = self else { return }
                let root = ActionDetailViewController(decoded: actionDataDecoded.0,
                                                      addressInfoIndex: actionDataDecoded.1,
                                                      chain: self.chain,
                                                      data: actionDataDecoded.2)
                let vc = RibbonViewController(rootViewController: root)
                self.show(vc, sender: self)
            }
        } else {
            return UITableViewCell()
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let cell = tableView.cellForRow(at: indexPath) as? DetailDisclosingCell {
            cell.action()
        }
    }

    func text(_ text: String, title: String?, expandableTitle: String?, copyText: String?, indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueCell(DetailExpandableTextCell.self, for: indexPath)
        cell.tableView = tableView
        cell.setTitle(title)
        cell.setText(text)
        cell.setCopyText(copyText)
        cell.setExpandableTitle(expandableTitle)
        return cell
    }

    func address(_ address: Address,
                 label: String?,
                 title: String?,
                 imageUri: URL? = nil,
                 indexPath: IndexPath,
                 browseURL: URL?,
                 prefix: String?) -> UITableViewCell {
        let cell = tableView.dequeueCell(DetailAccountCell.self, for: indexPath)
        cell.setAccount(address: address,
                        label: label,
                        title: title,
                        imageUri: imageUri,
                        browseURL: browseURL,
                        prefix: prefix)
        return cell
    }

    func disclosure(text: String, indexPath: IndexPath, action: @escaping () -> Void) -> UITableViewCell {
        let cell = tableView.dequeueCell(DetailDisclosingCell.self, for: indexPath)
        cell.action = action
        cell.setText(text)
        return cell
    }
}

fileprivate struct Section {
    let title: String
    let items: [SectionItem]
}

fileprivate struct SectionItem {
    let title: String?
    let value: Any
}
