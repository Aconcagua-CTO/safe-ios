//
//  MultisigNotification+ContentProvider.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 26.07.21.
//  Copyright © 2021 Gnosis Ltd. All rights reserved.
//

import Foundation
import CoreData

// NOTE:
// `NotificationServiceExtension` is intentionally kept lightweight and does not link
// all app-only dependencies. Avoid importing modules that aren't available to extensions.

private func formatTokenAmount(_ value: UInt256, decimals: Int, decimalSeparator: String) -> String {
    guard decimals > 0 else { return value.description }
    let digits = value.description
    // Insert decimal separator `decimals` digits from the end.
    if digits.count <= decimals {
        let zeros = String(repeating: "0", count: decimals - digits.count)
        var s = "0" + decimalSeparator + zeros + digits
        // Trim trailing zeros
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(decimalSeparator) { s.removeLast() }
        return s
    } else {
        let splitIndex = digits.index(digits.endIndex, offsetBy: -decimals)
        let whole = digits[..<splitIndex]
        let frac = digits[splitIndex...]
        var s = "\(whole)\(decimalSeparator)\(frac)"
        // Trim trailing zeros
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(decimalSeparator) { s.removeLast() }
        return s
    }
}

protocol NotificationContentProvider {
    func loadContent(completion: @escaping ((title: String, body: String)?) -> Void)
}

extension MultisigNotification: NotificationContentProvider {
    func loadContent(completion: @escaping ((title: String, body: String)?) -> Void) {
        switch self {
        case let .incomingNativeCoin(n):
            n.loadContent(completion: completion)
        case let .incomingToken(n):
            n.loadContent(completion: completion)
        case let .executedMultisigTransaction(n):
            n.loadContent(completion: completion)
        case let .newConfirmation(n):
            n.loadContent(completion: completion)
        case let .confirmationRequest(n):
            n.loadContent(completion: completion)
        case .unknown:
            completion(nil)
        }
    }
}

extension SafeNotification {
    func loadSafe(completion: @escaping (Safe?, NSManagedObjectContext) -> Void) {
        NotificationService.coreData.persistentContainer.performBackgroundTask { context in
            completion(safe(context: context, address: address, chainId: chainId), context)
        }
    }

    func safe(context: NSManagedObjectContext, address: AddressString, chainId: UInt256String) -> Safe? {
        do {
            let fr = Safe.fetchRequest().by(address: address.description, chainId: chainId.description)
            let safe = try context.fetch(fr).first
            return safe
        } catch {
            print("Failed to fetch safe: \(error)")
            return nil
        }
    }

    func keyInfo(context: NSManagedObjectContext, address: AddressString) -> KeyInfo? {
        do {
            let fr = KeyInfo.fetchRequest().by(address: address.address)
            let info = try context.fetch(fr).first
            return info
        } catch {
            print("Failed to fetch key info: \(error)")
            return nil
        }
    }

}

extension MultisigNotification.IncomingNativeCoin: NotificationContentProvider {
    func loadContent(completion: @escaping ((title: String, body: String)?) -> Void) {
        loadSafe { safeOrNil, _ in
            guard
                let safe = safeOrNil,
                let chain = safe.chain,
                let chainName = chain.name,
                let nativeCoin = chain.nativeCurrency,
                let symbol = nativeCoin.symbol
            else {
                completion((
                    title: String(format: NSLocalizedString("ui_notification_incoming_chain_id_title_format",
                                                            comment: "Incoming token title with chain id"),
                                  "\(chainId)"),
                    body: String(format: NSLocalizedString("ui_notification_incoming_native_body_format",
                                                           comment: "Incoming native token body"),
                                 address.address.truncatedInMiddle,
                                 "\(value)")
                ))
                return
            }
            let safeName = safe.name ?? address.address.truncatedInMiddle
            let amount = formatTokenAmount(
                value.value,
                decimals: Int(nativeCoin.decimals),
                decimalSeparator: Locale.autoupdatingCurrent.decimalSeparator ?? "."
            )

            let title = String(format: NSLocalizedString("ui_notification_incoming_symbol_title_format",
                                                         comment: "Incoming token title with symbol"),
                               symbol,
                               chainName)
            let body = String(format: NSLocalizedString("ui_notification_incoming_native_body_symbol_format",
                                                        comment: "Incoming native token body with symbol"),
                              safeName,
                              amount,
                              symbol)
            completion((title, body))
        }
    }
}

extension MultisigNotification.IncomingToken: NotificationContentProvider {
    func loadContent(completion: @escaping ((title: String, body: String)?) -> Void) {
        loadSafe { safeOrNil, _ in
            guard
                let safe = safeOrNil,
                let chain = safe.chain,
                let chainName = chain.name
            else {
                completion((
                    title: String(format: NSLocalizedString("ui_notification_incoming_chain_id_title_format",
                                                            comment: "Incoming token title with chain id"),
                                  "\(chainId)"),
                    body: String(format: NSLocalizedString("ui_notification_incoming_token_body_format",
                                                           comment: "Incoming token body fallback"),
                                 address.address.truncatedInMiddle)
                ))
                return
            }
            let safeName = safe.name ?? address.address.truncatedInMiddle

            let title = String(format: NSLocalizedString("ui_notification_incoming_token_title_format",
                                                         comment: "Incoming token title"),
                               chainName)
            var body = "\(safeName): "
            switch tokenType {
            case .erc20:
                body += NSLocalizedString("ui_notification_incoming_erc20_body",
                                          comment: "Incoming ERC20 body")
            case .erc721:
                body += NSLocalizedString("ui_notification_incoming_erc721_body",
                                          comment: "Incoming ERC721 body")
            case .unknown:
                body += NSLocalizedString("ui_notification_incoming_unknown_body",
                                          comment: "Incoming token body")
            }
            completion((title, body))
        }
    }
}

extension MultisigNotification.ExecutedMultisigTransaction: NotificationContentProvider {
    var localizedStatus: String {
        failed.value
            ? NSLocalizedString("ui_notification_tx_status_failed", comment: "Transaction failed status")
            : NSLocalizedString("ui_notification_tx_status_successful", comment: "Transaction successful status")
    }

    func loadContent(completion: @escaping ((title: String, body: String)?) -> Void) {
        loadSafe { safeOrNil, _ in
            guard
                let safe = safeOrNil,
                let chain = safe.chain,
                let chainName = chain.name
            else {
                completion((
                    title: String(format: NSLocalizedString("ui_notification_tx_title_chain_id_format",
                                                            comment: "Transaction title with chain id"),
                                  localizedStatus,
                                  "\(chainId)"),
                    body: String(format: NSLocalizedString("ui_notification_tx_body_format",
                                                           comment: "Transaction body format"),
                                 address.address.truncatedInMiddle,
                                 localizedStatus)
                ))
                return
            }
            let safeName = safe.name ?? address.address.truncatedInMiddle

            let title = String(format: NSLocalizedString("ui_notification_tx_title_format",
                                                         comment: "Transaction title format"),
                               localizedStatus,
                               chainName)
            let body = String(format: NSLocalizedString("ui_notification_tx_body_format",
                                                        comment: "Transaction body format"),
                              safeName,
                              localizedStatus)
            completion((title, body))
        }
    }
}

extension MultisigNotification.ConfirmationRequest: NotificationContentProvider {
    func loadContent(completion: @escaping ((title: String, body: String)?) -> Void) {
        loadSafe { safeOrNil, _ in
            guard
                let safe = safeOrNil,
                let chain = safe.chain,
                let chainName = chain.name
            else {
                completion((
                    title: String(format: NSLocalizedString("ui_notification_confirmation_required_chain_id_format",
                                                            comment: "Confirmation required title with chain id"),
                                  "\(chainId)"),
                    body: String(format: NSLocalizedString("ui_notification_confirmation_required_body_format",
                                                           comment: "Confirmation required body"),
                                 address.address.truncatedInMiddle)
                ))
                return
            }
            let safeName = safe.name ?? address.address.truncatedInMiddle

            let title = String(format: NSLocalizedString("ui_notification_confirmation_required_title_format",
                                                         comment: "Confirmation required title"),
                               chainName)
            let body = String(format: NSLocalizedString("ui_notification_confirmation_required_body_format",
                                                        comment: "Confirmation required body"),
                              safeName)
            completion((title, body))
        }
    }
}

extension MultisigNotification.NewConfirmation: NotificationContentProvider {
    func loadContent(completion: @escaping ((title: String, body: String)?) -> Void) {
        loadSafe { safeOrNil, context in
            guard
                let safe = safeOrNil,
                let chain = safe.chain,
                let chainName = chain.name
            else {
                completion((
                    title: String(format: NSLocalizedString("ui_notification_tx_confirmed_chain_id_format",
                                                            comment: "Transaction confirmed title with chain id"),
                                  "\(chainId)"),
                    body: String(format: NSLocalizedString("ui_notification_tx_confirmed_body_format",
                                                           comment: "Transaction confirmed body format"),
                                 address.address.truncatedInMiddle,
                                 owner.address.truncatedInMiddle)
                ))
                return
            }
            let safeName = safe.name ?? address.address.truncatedInMiddle
            let ownerInfo = keyInfo(context: context, address: owner)
            let ownerName = ownerInfo?.name ?? owner.address.truncatedInMiddle
            let title = String(format: NSLocalizedString("ui_notification_tx_confirmed_title_format",
                                                         comment: "Transaction confirmed title"),
                               chainName)
            let body = String(format: NSLocalizedString("ui_notification_tx_confirmed_body_format",
                                                        comment: "Transaction confirmed body format"),
                              safeName,
                              ownerName)
            completion((title, body))
        }
    }
}
