//
//  TransactionDetailCellBuilder.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 02.12.20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import Foundation
import UIKit
import SwiftCryptoTokenFormatter
import SwiftUI
import Version
import Solidity
import SafeWeb3

class TransactionDetailCellBuilder {

    private(set) weak var vc: UIViewController!
    private(set) weak var tableView: UITableView!

    // needed for proper safe selection for known addresses functionality. Also used to select the block explorer url.
    private(set) var chain: Chain
    private(set) var safe: Safe

    private lazy var dateFormatter: DateFormatter = {
        let d = DateFormatter()
        d.locale = .autoupdatingCurrent
        d.dateStyle = .medium
        d.timeStyle = .medium
        return d
    }()
    var result: [UITableViewCell] = []

    init(vc: UIViewController, tableView: UITableView, chain: Chain, safe: Safe) {
        self.vc = vc
        self.tableView = tableView
        self.chain = chain
        self.safe = safe

        tableView.registerCell(DetailExpandableTextCell.self)
        tableView.registerCell(DetailConfirmationCell.self)
        tableView.registerCell(DetailAccountCell.self)
        tableView.registerCell(DetailAccountAndTextCell.self)
        tableView.registerCell(DetailMultiAccountsCell.self)
        tableView.registerCell(DetailDisclosingCell.self)
        tableView.registerCell(ExternalURLCell.self)
        tableView.registerCell(DetailTransferInfoCell.self)
        tableView.registerCell(DetailRejectionInfoCell.self)
        tableView.registerCell(DetailStatusCell.self)
        tableView.registerCell(WarningTableViewCell.self)
    }

    func build(_ tx: SCGModels.TransactionDetails) -> [UITableViewCell] {
        result = []
        buildTransaction(tx)
        return result
    }

    func buildTransaction(_ tx: SCGModels.TransactionDetails) {
        let isCreationTx = buildCreationTx(tx)
        if !isCreationTx {
            buildWarning(tx)
            buildHeader(tx)
            buildAssetContract(tx)
            buildStatus(tx)
            buildMultisigInfo(tx)
            buildExecutedDate(tx)
            buildAdvanced(tx)
            buildOpenInExplorer(hash: tx.txHash)
        }
    }

    func buildCreationTx(_ tx: SCGModels.TransactionDetails) -> Bool {
        guard case let SCGModels.TxInfo.creation(creationTx) = tx.txInfo else {
            return false
        }
        buildStatus(tx)
        buildTransactionHash(creationTx)
        buildCreatorAddress(creationTx)
        buildMasterCopyUsed(creationTx)
        buildFactoryUsed(creationTx)
        buildCreatedDate(tx.executedAt)
        buildOpenInExplorer(hash: creationTx.transactionHash)
        return true
    }

    func buildFactoryUsed(_ creationTx: SCGModels.TxInfo.Creation) {
        if let factory = creationTx.factory?.value.address {
            let info = NamingPolicy.name(for: factory, chainId: chain.id!)
            address(factory,
                    label: info.name ?? creationTx.factory?.name ?? NSLocalizedString("ui_unknown_title", comment: "Unknown label"),
                    title: NSLocalizedString("ui_tx_factory_used_title", comment: "Factory used title"),
                    imageUri: info.imageUri ?? creationTx.factory?.logoUri,
                    browseURL: chain.browserURL(address: factory.checksummed),
                    prefix: chain.shortName)
        } else {
            text(NSLocalizedString("ui_tx_no_factory_used_title", comment: "No factory used title"),
                 title: NSLocalizedString("ui_tx_factory_used_title", comment: "Factory used title"),
                 expandableTitle: nil,
                 copyText: nil)
        }
    }

    func buildMasterCopyUsed(_ creationTx: SCGModels.TxInfo.Creation) {
        if let implementation = creationTx.implementation?.value.address {
            let info = NamingPolicy.name(for: implementation, chainId: chain.id!)
            address(
                implementation,
                label: info.name ?? creationTx.implementation?.name ?? NSLocalizedString("ui_unknown_title", comment: "Unknown label"),
                title: NSLocalizedString("ui_tx_base_contract_used_title", comment: "Base contract used title"),
                imageUri: info.imageUri ?? creationTx.implementation?.logoUri,
                browseURL: chain.browserURL(address: implementation.checksummed),
                prefix: chain.shortName)
        } else {
            text(
                NSLocalizedString("ui_tx_not_available_title", comment: "Not available label"),
                title: NSLocalizedString("ui_tx_base_contract_used_title", comment: "Base contract used title"),
                expandableTitle: nil,
                copyText: nil)
        }
    }

    func buildTransactionHash(_ creationTx: SCGModels.TxInfo.Creation) {
        text(
            creationTx.transactionHash.description,
            title: NSLocalizedString("ui_tx_transaction_hash_plain_title", comment: "Transaction hash title"),
            expandableTitle: nil,
            copyText: creationTx.transactionHash.description)
    }

    func buildCreatorAddress(_ creationTx: SCGModels.TxInfo.Creation) {
        let info = NamingPolicy.name(for: creationTx.creator, chainId: chain.id!)
        let creator = creationTx.creator.value.address
        return address(creator,
                       label: info.name,
                       title: NSLocalizedString("ui_tx_creator_address_title", comment: "Creator address title"),
                       imageUri: info.imageUri,
                       browseURL: chain.browserURL(address: creator.checksummed),
                       prefix: chain.shortName)
    }

    func buildHeader(_ tx: SCGModels.TransactionDetails) {

        switch tx.txInfo {

        case .transfer(let transferTx):
            let isOutgoing = transferTx.direction == .outgoing

            var address: Address
            var label: String?
            var addressLogoUri: URL?
            if isOutgoing {
                address = transferTx.recipient.value.address
                (label, addressLogoUri) = NamingPolicy.name(for: transferTx.recipient, chainId: chain.id!)
            } else {
                address = transferTx.sender.value.address
                (label, addressLogoUri) = NamingPolicy.name(for: transferTx.sender, chainId: chain.id!)
            }

            switch transferTx.transferInfo {

            case .erc20(let erc20Tx):
                buildTransferHeader(
                    address: address,
                    label: label,
                    addressLogoUri: addressLogoUri,
                    isOutgoing: isOutgoing,
                    status: tx.txStatus,
                    value: erc20Tx.value.value,
                    decimals: erc20Tx.decimals,
                    symbol: erc20Tx.tokenSymbol ?? "ERC20",
                    logoUri: erc20Tx.logoUri)

            case .erc721(let erc721Tx):
                buildTransferHeader(
                    address: address,
                    label: label,
                    addressLogoUri: addressLogoUri,
                    isOutgoing: isOutgoing,
                    status: tx.txStatus,
                    value: 1,
                    decimals: 0,
                    symbol: erc721Tx.tokenSymbol ?? "NFT",
                    logoUri: erc721Tx.logoUri,
                    logo: UIImage(named: "ico-nft-placeholder"),
                    detail: erc721Tx.tokenId.description)

            case .nativeCoin(let nativeCoinTx):
                let coin = Chain.nativeCoin!

                buildTransferHeader(
                    address: address,
                    label: label,
                    addressLogoUri: addressLogoUri,
                    isOutgoing: isOutgoing,
                    status: tx.txStatus,
                    value: nativeCoinTx.value.value,
                    decimals: UInt64(coin.decimals),
                    symbol: coin.symbol!,
                    logoUri: coin.logoUrl.map(\.absoluteString))

            case .unknown:
                buildTransferHeader(
                    address: address,
                    label: label,
                    addressLogoUri: addressLogoUri,
                    isOutgoing: isOutgoing,
                    status: tx.txStatus,
                    value: nil,
                    decimals: nil,
                    symbol: "",
                    logoUri: nil)

            }

        case .settingsChange(let settingsTx):

            switch settingsTx.settingsInfo {

            case .setFallbackHandler(let fallbackTx):
                let handler: Address = fallbackTx.handler.value.address
                var (label, imageUri) = NamingPolicy.name(for: fallbackTx.handler, chainId: chain.id!)
                if label == nil {
                    label = handler.isZero
                        ? NSLocalizedString("ui_not_set_title", comment: "Not set label")
                        : NSLocalizedString("ui_unknown_title", comment: "Unknown label")
                }
                address(
                    handler,
                    label: label,
                    title: NSLocalizedString("ui_tx_set_fallback_handler_title", comment: "Set fallback handler title"),
                    imageUri: imageUri,
                    browseURL: chain.browserURL(address: handler.checksummed),
                    prefix: chain.shortName,
                    showDelegateWarning: DelegateWarningCalculator.isUntrusted(txData: tx.txData)
                )

            case .addOwner(let addOwnerTx):
                let (label, imgageUri) = NamingPolicy.name(for: addOwnerTx.owner, chainId: chain.id!)
                addressAndText(
                    addOwnerTx.owner.value.address,
                    label: label,
                    imageUri: imgageUri,
                    addressTitle: NSLocalizedString("ui_tx_add_owner_title", comment: "Add owner title"),
                    text: "\(addOwnerTx.threshold)",
                    textTitle: NSLocalizedString("ui_tx_change_confirmations_title", comment: "Change required confirmations title"),
                    browseURL: chain.browserURL(address: addOwnerTx.owner.value.address.checksummed),
                    prefix: chain.shortName)

            case .removeOwner(let removeOwnerTx):
                let (label, imageUri) = NamingPolicy.name(for: removeOwnerTx.owner, chainId: chain.id!)
                addressAndText(
                    removeOwnerTx.owner.value.address,
                    label: label,
                    imageUri: imageUri,
                    addressTitle: NSLocalizedString("ui_tx_remove_owner_title", comment: "Remove owner title"),
                    text: "\(removeOwnerTx.threshold)",
                    textTitle: NSLocalizedString("ui_tx_change_confirmations_title", comment: "Change required confirmations title"),
                    browseURL: chain.browserURL(address: removeOwnerTx.owner.value.address.checksummed),
                    prefix: chain.shortName)

            case .swapOwner(let swapOwnerTx):
                let (oldOwnerLabel, oldOwnerImgageUri) = NamingPolicy.name(for: swapOwnerTx.oldOwner, chainId: chain.id!)
                let (newOwnerLabel, newOwnerImgageUri) = NamingPolicy.name(for: swapOwnerTx.newOwner, chainId: chain.id!)
                addresses(
                    [(address: swapOwnerTx.oldOwner.value.address,
                      label: oldOwnerLabel,
                      imageUri: oldOwnerImgageUri,
                      title: NSLocalizedString("ui_tx_remove_owner_title", comment: "Remove owner title"),
                      browseURL: chain.browserURL(address: swapOwnerTx.oldOwner.value.address.checksummed),
                      prefix: chain.shortName),
                     (address: swapOwnerTx.newOwner.value.address,
                      label: newOwnerLabel,
                      imageUri: newOwnerImgageUri,
                      title: NSLocalizedString("ui_tx_add_owner_title", comment: "Add owner title"),
                      browseURL: chain.browserURL(address: swapOwnerTx.newOwner.value.address.checksummed),
                      prefix: chain.shortName)
                    ])

            case .changeThreshold(let thresholdTx):
                text(
                    "\(thresholdTx.threshold)",
                    title: NSLocalizedString("ui_tx_change_confirmations_title", comment: "Change required confirmations title"),
                    expandableTitle: nil,
                    copyText: nil)

            case .changeImplementation(let implementationTx):
                let implementation = implementationTx.implementation.value.address
                var (label, imageUri) = NamingPolicy.name(for: implementationTx.implementation, chainId: chain.id!)
                if label == nil {
                    label = implementationTx.implementation.name ?? NSLocalizedString("ui_unknown_title", comment: "Unknown label")
                }
                address(implementation,
                        label: label,
                        title: NSLocalizedString("ui_tx_new_mastercopy_title", comment: "New mastercopy title"),
                        imageUri: imageUri,
                        browseURL: chain.browserURL(address: implementation.checksummed),
                        prefix: chain.shortName,
                        showDelegateWarning: DelegateWarningCalculator.isUntrusted(txData: tx.txData)
                )

            case .enableModule(let moduleTx):
                let (label, imageUri) = NamingPolicy.name(for: moduleTx.module, chainId: chain.id!)
                let module = moduleTx.module.value.address
                address(module,
                        label: label,
                        title: NSLocalizedString("ui_tx_enable_module_title", comment: "Enable module title"),
                        imageUri: imageUri,
                        browseURL: chain.browserURL(address: module.checksummed),
                        prefix: chain.shortName,
                        showDelegateWarning: DelegateWarningCalculator.isUntrusted(txData: tx.txData)
                )

            case .disableModule(let moduleTx):
                let (label, imageUri) = NamingPolicy.name(for: moduleTx.module, chainId: chain.id!)
                let module = moduleTx.module.value.address
                address(module,
                        label: label,
                        title: NSLocalizedString("ui_tx_disable_module_title", comment: "Disable module title"),
                        imageUri: imageUri,
                        browseURL: chain.browserURL(address: module.checksummed),
                        prefix: chain.shortName,
                        showDelegateWarning: DelegateWarningCalculator.isUntrusted(txData: tx.txData)
                )
                
            case .setGuard(let guardTx):
                let (label, imageUri) = NamingPolicy.name(for: guardTx.guard, chainId: chain.id!)
                let guardContract = guardTx.guard.value.address
                address(guardContract,
                        label: label,
                        title: NSLocalizedString("ui_tx_set_guard_title", comment: "Set guard title"),
                        imageUri: imageUri,
                        browseURL: chain.browserURL(address: guardContract.checksummed),
                        prefix: chain.shortName,
                        showDelegateWarning: DelegateWarningCalculator.isUntrusted(txData: tx.txData)
                )
                
            case .deleteGuard:
                text(NSLocalizedString("ui_tx_delete_guard_title", comment: "Delete guard title"),
                     title: NSLocalizedString("ui_tx_settings_change_title", comment: "Settings change title"),
                     expandableTitle: nil,
                     copyText: nil)

            case .unknown:
                text(NSLocalizedString("ui_tx_unknown_operation_title", comment: "Unknown operation title"),
                     title: NSLocalizedString("ui_tx_settings_change_title", comment: "Settings change title"),
                     expandableTitle: nil,
                     copyText: nil)
            }

        case .custom(let customTx):
            let (label, addressLogoUri) = NamingPolicy.name(for: customTx.to, chainId: chain.id!)
            var title = NSLocalizedString("ui_tx_interact_with_prefix", comment: "Prefix label for custom transaction interaction, shown before the contract name/address")
            let amount = Int256(customTx.value.value)
            if customTx.value != "0"  {
                let nativeCoinDecimals = chain.nativeCurrency!.decimals

                let decimalAmount = BigDecimal(amount, Int(nativeCoinDecimals))
                let amount = TokenFormatter().string(
                        from: decimalAmount,
                        decimalSeparator: Locale.autoupdatingCurrent.decimalSeparator ?? ".",
                        thousandSeparator: Locale.autoupdatingCurrent.groupingSeparator ?? ",",
                        forcePlusSign: false
                )
                
                if let currencySymbol = chain.nativeCurrency?.symbol {
                    title = String(format: NSLocalizedString("ui_tx_interact_send_amount_currency_title_format", comment: "Interact with send amount and currency title"), amount, currencySymbol)
                } else {
                    title = String(format: NSLocalizedString("ui_tx_interact_send_amount_title_format", comment: "Interact with send amount title"), amount)
                }
            }

            address(customTx.to.value.address,
                label: label,
                title: title,
                imageUri: addressLogoUri,
                browseURL: chain.browserURL(address: customTx.to.value.address.checksummed),
                prefix: chain.shortName,
                showDelegateWarning: DelegateWarningCalculator.isUntrusted(txData: tx.txData)
            )
            buildActions(tx)
            buildHexData(tx)
        case .rejection(_):
            if case let SCGModels.TransactionDetails.DetailedExecutionInfo.multisig(multisigInfo)? = tx.detailedExecutionInfo {
                rejectionHeader(nonce: multisigInfo.nonce.value, isQueued: tx.txStatus.isInQueue)
            } else {
                rejectionHeader(nonce: nil, isQueued: tx.txStatus.isInQueue)
            }
        case .swapOrder(let orderInfo):
            text(orderInfo.swapOrderDisplayName,
                 title: NSLocalizedString("ui_tx_contract_interaction_section_title", comment: "Contract interaction section title"),
                 expandableTitle: nil,
                 copyText: nil)
            externalURL(text: NSLocalizedString("ui_tx_order_details_title", comment: "Order details title"), url: orderInfo.explorerUrl)
        case .swapTransfer(let orderInfo):
            text(orderInfo.swapTransferDisplayName,
                 title: NSLocalizedString("ui_tx_contract_interaction_section_title", comment: "Contract interaction section title"),
                 expandableTitle: nil,
                 copyText: nil)
            externalURL(text: NSLocalizedString("ui_tx_order_details_title", comment: "Order details title"), url: orderInfo.explorerUrl)
        case .twapOrder(let order):
            text(order.displayName,
                 title: NSLocalizedString("ui_tx_contract_interaction_section_title", comment: "Contract interaction section title"),
                 expandableTitle: nil,
                 copyText: nil)
        case .stake(let stake):
            text(stake.displayName,
                 title: NSLocalizedString("ui_tx_contract_interaction_section_title", comment: "Contract interaction section title"),
                 expandableTitle: nil,
                 copyText: nil)
        
        case .creation(_):
            // ignore
            fallthrough
        case .unknown:
            // ignore
            break
        }
    }

    // MARK: - Transaction Screen Pieces

    func buildTransferHeader(
        address: Address,
        label: String?,
        addressLogoUri: URL?,
        isOutgoing: Bool,
        status txStatus: SCGModels.TxStatus,
        value: UInt256?,
        decimals: UInt64?,
        symbol: String,
        logoUri: String?,
        logo: UIImage? = UIImage(named: "ico-token-placeholder"),
        detail: String? = nil
    ) {
        let tokenText: String
        if let value = value {
            let decimalAmount = BigDecimal(Int256(value) * (isOutgoing ? -1 : +1),
                                           decimals.flatMap { Int($0) } ?? 0)

            let amount = TokenFormatter().string(
                from: decimalAmount,
                decimalSeparator: Locale.autoupdatingCurrent.decimalSeparator ?? ".",
                thousandSeparator: Locale.autoupdatingCurrent.groupingSeparator ?? ",",
                forcePlusSign: true
            )

            tokenText = "\(amount) \(symbol)"
        } else {
            tokenText = NSLocalizedString("ui_tx_unknown_token_title", comment: "Unknown token title")
        }


        let style: GNOTextStyle = isOutgoing ? .headline : .headlineBaseSuccess

        let iconURL = logoUri.flatMap { URL(string: $0) }

        let alpha: CGFloat = [SCGModels.TxStatus.cancelled, .failed].contains(txStatus) ? 0.5 : 1

        transfer(
            token: tokenText,
            style: style,
            icon: logo,
            iconURL: iconURL,
            alpha: alpha,
            detail: detail,
            address: address,
            label: label,
            addressLogoUri: addressLogoUri,
            isOutgoing: isOutgoing)
    }
    
    func validate(tx: SCGModels.TransactionDetails, safe: Safe) throws {
        guard tx.txStatus.isAwatingConfiramtions || tx.txStatus == .awaitingExecution else {
            // don't warn outside of signature or execution requests
            return
        }
        
        // safe has owners
        guard let ownersInfo = safe.ownersInfo, !ownersInfo.isEmpty else {
            // not enough data for further checks
            return
        }
        let ownerAddresses = ownersInfo.map(\.address)
        
        // transaction has confirmations
        guard let txMultisigInfo = tx.multisigInfo else {
            // not a kind of transaction we can take a look into
            return
        }
        
        guard !txMultisigInfo.confirmations.isEmpty else {
            throw NSLocalizedString("ui_tx_no_confirmations_error", comment: "Transaction has no confirmations error")
        }
        
        // all confirming addresses are from safe owners
        guard txMultisigInfo.confirmations.allSatisfy({ confirmation in
            ownerAddresses.contains(confirmation.signer.value.address)
        }) else {
            throw NSLocalizedString("ui_tx_confirmations_not_owners_error", comment: "Confirmations not owners error")
        }
        
        // transaction hash is valid
        guard var transaction = Transaction(tx: tx),
              let contractVersion = safe.semVer,
              let chainId = safe.chain?.id
        else {
            // not enough information for further checks
            return
        }
        transaction.safe = AddressString(stringLiteral: safe.displayAddress)
        transaction.safeVersion = contractVersion
        transaction.chainId = chainId
        
        guard
            let computedSafeTxHash = transaction.safeTransactionHash(),
            transaction.safeTxHash == computedSafeTxHash
        else {
            throw NSLocalizedString("ui_tx_invalid_safetxhash_error", comment: "Invalid safeTxHash error")
        }
        
        // all confirming signatures are from a confirming addresses
        func signer(of signature: Data) -> Address? {
            guard signature.count >= 65 else {
                // cannot decode signature
                return nil
            }
            
            let r: Data /* 32 bytes */ = signature[0..<32]
            let s: Data /* 32 bytes */ = signature[32..<64]
            let v: UInt8 = signature[64]
            
            let contractSignature: UInt8 = 0
            let approvedHashSignature: UInt8 = 1
            let ethSignSignature: ClosedRange<UInt8> = (31...UInt8.max)
            
            if contractVersion >= Version(1, 1, 0) {
                switch v {
                case contractSignature, approvedHashSignature:
                    let owner = (try? Sol.Address(data: r)).map { Address($0) }
                    return owner
                    
                case ethSignSignature:
                    let hash = computedSafeTxHash.hash
                    let message = "\u{19}Ethereum Signed Message:\n\(hash.count)".data(using: .utf8)! + hash
                    
                    let pubKey = try? EthereumPublicKey(
                        message: message.makeBytes(),
                        v: EthereumQuantity(quantity: (BigUInt(v) - 4) - 27),
                        r: EthereumQuantity(r.makeBytes()),
                        s: EthereumQuantity(s.makeBytes())
                    )

                    let owner = pubKey.map(\.address).map(Address.init)
                    return owner
                    
                default:
                    let message = transaction.encodeTransactionData()

                    let pubKey = try? EthereumPublicKey(
                        message: message.makeBytes(),
                        v: EthereumQuantity(quantity: v >= 27 ? BigUInt(v) - 27 : BigUInt(v)),
                        r: EthereumQuantity(r.makeBytes()),
                        s: EthereumQuantity(s.makeBytes())
                    )
                    let owner = pubKey.map(\.address).map(Address.init)
                    return owner
                }
            } else {
                switch v {
                case contractSignature, approvedHashSignature:
                    let owner = (try? Sol.Address(data: r)).map { Address($0) }
                    return owner
                default:
                    let message = transaction.encodeTransactionData()

                    let pubKey = try? EthereumPublicKey(
                        message: message.makeBytes(),
                        v: EthereumQuantity(quantity: v >= 27 ? BigUInt(v) - 27 : BigUInt(v)),
                        r: EthereumQuantity(r.makeBytes()),
                        s: EthereumQuantity(s.makeBytes())
                    )
                    let owner = pubKey.map(\.address).map(Address.init)
                    return owner
                }
            }
        }
        
        guard txMultisigInfo.confirmations.allSatisfy({ confirmation in
            signer(of: confirmation.signature.data) == confirmation.signer.value.address
        }) else {
            throw NSLocalizedString("ui_tx_signatures_not_owners_error", comment: "Signatures not owners error")
        }
    }
    
    func buildWarning(_ tx: SCGModels.TransactionDetails) {
        do {
            guard let aSafe = Safe.by(address: tx.safeAddress.description, chainId: chain.id!) else {
                return
            }
            try validate(tx: tx, safe: aSafe)
        } catch {
            let cell = newCell(WarningTableViewCell.self)
            cell.set(title: NSLocalizedString("ui_warning_title", comment: "Warning title"),
                     description: error.localizedDescription)
            result.append(cell)
        }
    }


    func buildActions(_ tx: SCGModels.TransactionDetails) {
        if let dataDecoded = tx.txData?.dataDecoded {
            let addressInfoIndex = tx.txData?.addressInfoIndex

            if dataDecoded.method == "multiSend",
               let param = dataDecoded.parameters?.first,
               param.type == "bytes",
               case let SCGModels.DataDecoded.Parameter.ValueDecoded.multiSend(multiSendTxs)? = param.valueDecoded {

                disclosure(text: String(format: NSLocalizedString("ui_tx_multisend_actions_title_format", comment: "Multisend actions title"),
                                        multiSendTxs.count)) { [weak self] in
                    guard let `self` = self else { return }
                    let root = MultiSendListTableViewController(transactions: multiSendTxs,
                                                                addressInfoIndex: addressInfoIndex,
                                                                chain: self.chain,
                                                                safe: self.safe)
                    let vc = RibbonViewController(rootViewController: root)
                    self.vc.show(vc, sender: self)
                }
            } else {
                disclosure(text: String(format: NSLocalizedString("ui_tx_action_method_title_format", comment: "Action title with method"),
                                        dataDecoded.method)) { [weak self] in
                    guard let `self` = self else { return }
                    let root = ActionDetailViewController(decoded: dataDecoded,
                                                          addressInfoIndex: addressInfoIndex,
                                                          chain: self.chain,
                                                          safe: self.safe,
                                                          data: tx.txData?.hexData)
                    let vc = RibbonViewController(rootViewController: root)
                    self.vc.show(vc, sender: self)
                }
            }
        }
    }

    func buildHexData(_ tx: SCGModels.TransactionDetails) {
        if let data = tx.txData?.hexData {
            text("\(data)",
                 title: NSLocalizedString("ui_tx_data_title", comment: "Transaction data title"),
                 expandableTitle: String(format: NSLocalizedString("ui_tx_bytes_title_format", comment: "Bytes count title"),
                                         "\(data.data.count)"),
                 copyText: "\(data)")
        }
    }

    func buildAssetContract(_ tx: SCGModels.TransactionDetails) {
        switch tx.txInfo {
        case .transfer(let transferTx):
            switch transferTx.transferInfo {
            case .erc721(let erc721Tx):
                let tokenAddress = erc721Tx.tokenAddress.address
                address(tokenAddress,
                        label: NSLocalizedString("ui_tx_asset_contract_title", comment: "Asset contract label"),
                        title: nil,
                        browseURL: chain.browserURL(address: tokenAddress.checksummed),
                        prefix: chain.shortName)
            default:
                break
            }
        default:
            break
        }
    }

    func buildStatus(_ tx: SCGModels.TransactionDetails) {
        var type = ""
        var tag: String = ""
        var icon: UIImage?
        var imageURL: URL?

        switch tx.txInfo {
        case .transfer(let transferTx):
            let isOutgoing = transferTx.direction == .outgoing
            type = isOutgoing
                ? NSLocalizedString("ui_tx_outgoing_transfer_title", comment: "Outgoing transfer title")
                : NSLocalizedString("ui_tx_incoming_transfer_title", comment: "Incoming transfer title")
            icon = isOutgoing ? UIImage(named: "ico-outgoing-tx") : UIImage(named: "ico-incomming-tx")?.withTintColor(.success)
        case .settingsChange(_):
            type = NSLocalizedString("ui_tx_modify_settings_title", comment: "Modify settings title")
            icon = UIImage(named: "ico-settings-tx")
        case .custom(_):
            if let safeAppInfo = tx.safeAppInfo {
                type = safeAppInfo.name
                imageURL = URL(string: safeAppInfo.logoUri)
                tag = NSLocalizedString("ui_tx_app_tag", comment: "Transaction app tag")
                icon = UIImage(named: "ico-custom-tx")
            } else {
            type = NSLocalizedString("ui_tx_contract_interaction_title", comment: "Contract interaction title")
                icon = UIImage(named: "ico-custom-tx")
            }
        case .rejection(_):
            type = NSLocalizedString("ui_tx_onchain_rejection_title", comment: "Transaction type label for on-chain rejection")
            icon = UIImage(named: "ico-rejection-tx")
        case .creation(_):
            type = NSLocalizedString("ui_tx_safe_account_created_title", comment: "Transaction type label for Safe Account creation")
            icon = UIImage(named: "ico-settings-tx")
        case .swapOrder(let order):
            type = order.swapOrderDisplayName
            icon = UIImage(named: "ico-custom-tx")
        case .swapTransfer(let order):
            type = order.swapTransferDisplayName
            icon = UIImage(named: "ico-custom-tx")
        case .twapOrder(let order):
            type = order.displayName
            icon = UIImage(named: "ico-custom-tx")
        case .stake(let stake):
            type = stake.displayName
            icon = UIImage(named: "ico-custom-tx")
        case .unknown:
            type = NSLocalizedString("ui_tx_unknown_operation_title", comment: "Unknown operation title")
            icon = UIImage(named: "ico-custom-tx")
        }

        status(tx.txStatus, isReplaced: isReplacedTransaction(tx), type: type, icon: icon, iconURL: imageURL, address: nil, tag: tag)
    }

    func buildMultisigInfo(_ tx: SCGModels.TransactionDetails) {
        guard case let SCGModels.TransactionDetails.DetailedExecutionInfo.multisig(multisigInfo)? =
                tx.detailedExecutionInfo else {
            return
        }

        confirmation(multisigInfo.confirmations.map { $0.signer.value.address },
                     required: Int(multisigInfo.confirmationsRequired),
                     status: tx.txStatus,
                     executor: multisigInfo.executor?.value.address,
                     isRejectionTx: tx.txInfo.isRejection,
                     isReplaced: isReplacedTransaction(tx))

        buildCreatedDate(multisigInfo.submittedAt)
    }

    func buildCreatedDate(_ date: Date?) {
        guard let date = date else { return }
        text(
            dateFormatter.string(from: date),
            title: NSLocalizedString("ui_tx_created_title", comment: "Created date title"),
            expandableTitle: nil,
            copyText: nil)
    }

    func buildExecutedDate(_ tx: SCGModels.TransactionDetails) {
        guard let executedAt = tx.executedAt else { return }
        text(
            dateFormatter.string(from: executedAt),
            title: NSLocalizedString("ui_tx_executed_title", comment: "Executed date title"),
            expandableTitle: nil,
            copyText: nil)
    }

    func buildAdvanced(_ tx: SCGModels.TransactionDetails) {
        switch tx.txInfo {
        case .transfer(let transferTx):
            guard transferTx.direction != .incoming else { return }
            fallthrough
        default:
            disclosure(text: NSLocalizedString("ui_tx_advanced_title", comment: "Advanced details title")) { [weak self] in
                guard let `self` = self else { return }
                let vc = AdvancedTransactionDetailsViewController(tx, chain: self.chain)
                let ribbonVC = RibbonViewController(rootViewController: vc)
                self.vc.show(ribbonVC, sender: self)
            }
            break
        }
    }

    func buildOpenInExplorer(hash: DataString?) {
        guard
            let txHash = hash?.description
        else { return }
        let url = chain.browserURL(txHash: txHash)
        externalURL(text: NSLocalizedString("ui_tx_view_on_block_explorer_title", comment: "View on block explorer title"), url: url)
    }

    // MARK: - Cell Builder

    func disclosure(text: String, action: @escaping () -> Void) {
        let cell = newCell(DetailDisclosingCell.self)
        cell.action = action
        cell.setText(text)
        result.append(cell)
    }

    func externalURL(text: String, url: URL) {
        let cell = newCell(ExternalURLCell.self)
        cell.setText(text, url: url)
        result.append(cell)
    }

    func text(_ text: String, title: String, expandableTitle: String?, copyText: String?) {
        let cell = newCell(DetailExpandableTextCell.self)
        cell.tableView = tableView
        cell.setTitle(title)
        cell.setText(text)
        cell.setCopyText(copyText)
        cell.setExpandableTitle(expandableTitle)
        result.append(cell)
    }

    func confirmation(_ confirmations: [Address], required: Int, status: SCGModels.TxStatus, executor: Address?, isRejectionTx: Bool, isReplaced: Bool) {
        let cell = newCell(DetailConfirmationCell.self)
        cell.setConfirmations(confirmations,
                              chain: chain,
                              required: required,
                              status: status,
                              executor: executor,
                              isRejectionTx: isRejectionTx,
                              isReplaced: isReplaced)
        result.append(cell)
    }

    func status(_ status: SCGModels.TxStatus, isReplaced: Bool, type: String, icon: UIImage?, iconURL: URL? = nil, address: AddressString? = nil, tag: String = "") {
        let cell = newCell(DetailStatusCell.self)
        cell.setTitle(type)

        cell.setStatus(status, isReplaced: isReplaced)
        cell.set(tag: tag)
        if let imageURL = iconURL, let placeholderAddress = address {
            cell.set(contractImageUrl: imageURL, contractAddress: placeholderAddress)
        } else if let imageURL = iconURL {
            cell.set(imageUrl: imageURL, placeholder: icon)
        } else if let image = icon {
            cell.setIcon(image)
        } else if let placeholderAddress = address {
            cell.set(contractAddress: placeholderAddress)
        }

        result.append(cell)
    }

    private func isReplacedTransaction(_ tx: SCGModels.TransactionDetails) -> Bool {
        guard let safeNonce = safe.nonce else { return false }
        guard tx.txStatus.isInQueue else { return false }
        guard let txNonce = tx.multisigInfo?.nonce.value else { return false }
        return safeNonce > txNonce
    }

    func transfer(token: String,
                  style: GNOTextStyle,
                  icon: UIImage?,
                  iconURL: URL?,
                  alpha: CGFloat,
                  detail: String?,
                  address: Address,
                  label: String?, // todo: rename
                  addressLogoUri: URL?,
                  isOutgoing: Bool) {
        let cell = newCell(DetailTransferInfoCell.self)
        cell.setToken(text: token, style: style)
        cell.setToken(image: iconURL, placeholder: icon)
        cell.setToken(alpha: alpha)
        cell.setDetail(detail)
        cell.setAddress(address,
                        label: label,
                        imageUri: addressLogoUri,
                        browseURL: chain.browserURL(address: address.checksummed),
                        prefix: chain.shortName)
        cell.setOutgoing(isOutgoing)
        result.append(cell)
    }

    func rejectionHeader(nonce: UInt256?, isQueued: Bool) {
        let cell = newCell(DetailRejectionInfoCell.self)
        cell.setNonce(nonce, showHelpLink: isQueued)
        result.append(cell)
    }

    func address(_ address: Address,
                 label: String?,
                 title: String?,
                 imageUri: URL? = nil,
                 browseURL: URL? = nil,
                 prefix: String? = nil,
                 showDelegateWarning: Bool = false) {

        let cell = newCell(DetailAccountCell.self)
        cell.setAccount(address: address,
                        label: label,
                        title: title,
                        imageUri: imageUri,
                        browseURL: browseURL,
                        prefix: prefix,
                        showDelegateWarning: showDelegateWarning)
        result.append(cell)
    }

    func addressAndText(_ address: Address,
                        label: String?,
                        imageUri: URL?,
                        addressTitle: String,
                        text: String,
                        textTitle: String,
                        browseURL: URL?,
                        prefix: String?) {
        let cell = newCell(DetailAccountAndTextCell.self)
        cell.setText(title: textTitle, details: text)
        cell.setAccount(address: address,
                        label: label,
                        title: addressTitle,
                        imageUri: imageUri,
                        browseURL: browseURL,
                        prefix: prefix)
        result.append(cell)
    }

    func addresses(_ accounts: [(address: Address,
                                 label: String?,
                                 imageUri: URL?,
                                 title: String?,
                                 browseURL: URL?,
                                 prefix: String?)]) {
        let cell = newCell(DetailMultiAccountsCell.self)
        cell.setAccounts(accounts: accounts)
        result.append(cell)
    }

    func newCell<T: UITableViewCell>(_ cls: T.Type, reuseId: String? = nil) -> T {
        tableView.dequeueCell(cls, reuseID: reuseId)
    }
}

extension SCGModels.Operation {
    static let strings: [Self: String] = [
        .call: "call",
        .delegate: "delegateCall"
    ]
    var string: String {
        Self.strings[self]!
    }
}

extension SCGModels.TxInfo {
    var isRejection: Bool {
        if case SCGModels.TxInfo.rejection(_) = self {
            return true
        }

        return false
    }
}
