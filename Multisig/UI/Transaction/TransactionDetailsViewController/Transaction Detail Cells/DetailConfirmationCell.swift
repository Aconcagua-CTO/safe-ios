//
//  DetailConfirmationCell.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 02.12.20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import UIKit

class DetailConfirmationCell: UITableViewCell {
    @IBOutlet private weak var stackView: UIStackView!

    func setConfirmations(_ confirmations: [Address],
                          chain: Chain,
                          required: Int,
                          status: SCGModels.TxStatus,
                          executor: Address?,
                          isRejectionTx: Bool = false,
                          isReplaced: Bool = false) {
        let bounds = contentView.bounds
        var views: [UIView] = []

        views.append(isRejectionTx ? RejectionCreatedPiece(frame: bounds) : ConfirmationCreatedPiece(frame: bounds))

        views += confirmations.map { address -> ConfirmationConfirmedPiece in
            let v = ConfirmationConfirmedPiece(frame: bounds)
            v.setText(NSLocalizedString("ui_tx_status_confirmed", comment: "Transaction confirmed status"))
            let keyInfo = try? KeyInfo.keys(addresses: [address]).first
            let (name, _) = NamingPolicy.name(for: address, info: nil, chainId: chain.id!)
            v.setAddress(address,
                         label: name,
                         badgeName: keyInfo?.keyType.badgeName,
                         browseURL: chain.browserURL(address: address.checksummed),
                         prefix: chain.shortName)
            return v
        }

        if isReplaced {
            let status = ConfirmationStatusPiece(frame: bounds)
            status.setText(NSLocalizedString("ui_tx_status_replaced", comment: "Transaction replaced status"), style: .headline)
            status.setSymbol("arrow.triangle.2.circlepath", color: .labelSecondary)
            views.append(status)
        } else {
            switch status {
        case .awaitingConfirmations, .awaitingYourConfirmation:
            let confirmationsRemaining = required - confirmations.count
            if confirmationsRemaining > 0 {
                let status = ConfirmationStatusPiece(frame: bounds)
                let remainingText = String(format: NSLocalizedString("ui_tx_execute_more_confirmations_format", comment: "Execute button with confirmations remaining"), "\(confirmationsRemaining)")
                status.setText(remainingText, style: .callout)
                status.setSymbol("circle", color: .labelSecondary)
                views.append(status)
            } else {
                let status = executionPiece(frame: bounds)
                views.append(status)
            }
            
        case .awaitingExecution:
            let status = executionPiece(frame: bounds)
            views.append(status)

        case .cancelled:
            let status = ConfirmationStatusPiece(frame: bounds)
            status.setText(NSLocalizedString("ui_tx_status_cancelled", comment: "Transaction cancelled status"), style: .headline)
            status.setSymbol("xmark.circle", color: .black)
            views.append(status)

        case .failed:
            let status = ConfirmationStatusPiece(frame: bounds)
            status.setText(NSLocalizedString("ui_tx_status_failed", comment: "Transaction failed status"), style: .headlineError)
            status.setSymbol("xmark.circle", color: .error)
            views.append(status)

        case .success:
            if let address = executor {
                let success = ConfirmationConfirmedPiece(frame: bounds)
                success.setText(NSLocalizedString("ui_tx_status_executed", comment: "Transaction executed status"))
                success.setShowsBar(false)
                let keyInfo = try? KeyInfo.keys(addresses: [address]).first
                let (name, _) = NamingPolicy.name(for: address, info: nil, chainId: chain.id!)
                success.setAddress(address,
                                   label: name,
                                   badgeName: keyInfo?.keyType.badgeName,
                                   browseURL: chain.browserURL(address: address.checksummed),
                                   prefix: chain.shortName)
                views.append(success)
            } else {
                let status = ConfirmationStatusPiece(frame: bounds)
                status.setText(NSLocalizedString("ui_tx_status_executed", comment: "Transaction executed status"), style: .headline)
                status.setSymbol("checkmark.circle", color: .success)
                views.append(status)
            }

        case .pending:
            let status = ConfirmationStatusPiece(frame: bounds)
            status.setText(NSLocalizedString("ui_tx_status_pending", comment: "Transaction pending status"), style: .headline)
            status.setSymbol("circle", color: .success)
            views.append(status)
            }
        }

        for view in stackView.arrangedSubviews {
            view.removeFromSuperview()
        }

        stackView.translatesAutoresizingMaskIntoConstraints = false
        for view in views {
            stackView.addArrangedSubview(view)
        }
    }

    private func executionPiece(frame: CGRect) -> UIView {
        let status = ConfirmationStatusPiece(frame: bounds)
        status.setText("Execute", style: .headlineSecondary)
        status.setSymbol("circle", color: .success)
        return status
    }
}
