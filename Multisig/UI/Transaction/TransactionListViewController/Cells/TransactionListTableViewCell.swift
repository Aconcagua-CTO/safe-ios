//
//  TransactionListTableViewCell.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 18.11.20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import UIKit
import SwiftUI

class TransactionListTableViewCell: SwiftUITableViewCell {
    @IBOutlet private weak var conflictTypeButtonBarView: UIView!
    @IBOutlet private weak var conflictTypeView: UIView!
    @IBOutlet private weak var typeImageView: UIImageView!
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var nonceLabel: UILabel!
    @IBOutlet private weak var dateLabel: UILabel!
    @IBOutlet private weak var infoLabel: UILabel!
    @IBOutlet private weak var appendixLabel: UILabel!
    @IBOutlet private weak var statusIconImageView: UIImageView!
    @IBOutlet private weak var statusLabel: UILabel!
    @IBOutlet private weak var bottomStackView: UIStackView!
    @IBOutlet private weak var confirmationsCountLabel: UILabel!
    @IBOutlet private weak var confirmationsCountImageView: UIImageView!
    @IBOutlet private weak var highlightBarView: UIView!
    @IBOutlet private weak var highlightView: UIView!
    @IBOutlet private weak var tagView: TagView!

    override func awakeFromNib() {
        super.awakeFromNib()
        titleLabel.setStyle(.headline)
        nonceLabel.setStyle(.footnoteSecondary)
        dateLabel.setStyle(.footnoteSecondary)
        infoLabel.setStyle(.headline)
        appendixLabel.setStyle(.footnote)
        statusLabel.setStyle(.footnote)
        confirmationsCountLabel.setStyle(.footnote)
        highlightView.clipsToBounds = true
        highlightView.layer.cornerRadius = 4
    }

    func set(title: String) {
        titleLabel.text = title
    }

    func set(image: UIImage) {
        typeImageView.contentMode = .center
        typeImageView.image = image
    }

    func set(contractImageUrl: URL? = nil, contractAddress: AddressString) {
        typeImageView.contentMode = .scaleAspectFit
        typeImageView.setCircleImage(url: contractImageUrl, address: contractAddress.address)
    }

    func set(imageUrl: URL? = nil, placeholder: UIImage?) {
        typeImageView.contentMode = .scaleAspectFit
        typeImageView.setCircleShapeImage(url: imageUrl, placeholder: placeholder)
    }

    func set(conflictType: SCGModels.ConflictType) {
        conflictTypeView.isHidden = conflictType == .none
        conflictTypeButtonBarView.isHidden = conflictType == .end
        if conflictType != .none {
            nonceLabel.isHidden = true
        } else {
            nonceLabel.isHidden = (nonceLabel.text ?? "").isEmpty
        }
    }

    func set(nonce: String) {
        nonceLabel.text = nonce
        nonceLabel.isHidden = nonce.isEmpty
    }

    func set(date: String) {
        dateLabel.text = date
    }

    func set(info: String, color: UIColor = .labelPrimary) {
        infoLabel.text = info
        infoLabel.textColor = color
    }

    func set(confirmationsSubmitted: UInt64, confirmationsRequired: UInt64) {
        let color = confirmationColor(confirmationsSubmitted, confirmationsRequired)
        confirmationsCountLabel.text = "\(confirmationsSubmitted) out of \(confirmationsRequired)"
        confirmationsCountLabel.textColor = color
        confirmationsCountImageView.tintColor = color
    }

    func set(status: SCGModels.TxStatus, isReplaced: Bool = false, overrideStatusText: String? = nil) {
        let statusText = overrideStatusText ?? (isReplaced ? "Replaced" : transactionListStatusTitle(for: status))
        statusLabel.text = statusText
        appendixLabel.text = statusText

        let isWaiting = isReplaced ? false : status.isWaiting
        appendixLabel.isHidden = isWaiting
        bottomStackView.isHidden = !isWaiting

        let color = isReplaced ? UIColor.labelSecondary : statusColor(status: status)
        statusLabel.textColor = color
        appendixLabel.textColor = color
        self.contentView.alpha = isReplaced ? 0.5 : containerViewAlpha(status: status)

        applyStrikethrough(titleLabel, enabled: isReplaced)
        applyStrikethrough(infoLabel, enabled: isReplaced)
        applyStrikethrough(nonceLabel, enabled: isReplaced)
    }

    private func transactionListStatusTitle(for status: SCGModels.TxStatus) -> String {
        if status == .awaitingExecution {
            return "En ejecución"
        }
        return status.title
    }

    func set(highlight: Bool) {
        highlightBarView.isHidden = !highlight
        highlightView.backgroundColor = highlight ? .errorBackground : .clear
    }

    func set(tag: String) {
        tagView.isHidden = tag.isEmpty
        tagView.set(title: tag)
    }

    private func statusColor(status: SCGModels.TxStatus) -> UIColor {
        switch status {
        case .awaitingExecution, .awaitingConfirmations, .awaitingYourConfirmation, .pending:
            return .warning
        case .failed:
            return .error
        case .cancelled:
            return .labelSecondary
        case .success:
            return .baseSuccess
        }
    }

    private func containerViewAlpha(status: SCGModels.TxStatus) -> CGFloat {
        status.isFailed ? 0.5 : 1
    }

    private func confirmationColor(_ confirmationsSubmitted: UInt64 = 0, _ confirmationsRequired: UInt64 = 0) -> UIColor {
        let reminingConfirmations = confirmationsSubmitted > confirmationsRequired ? 0 : confirmationsRequired - confirmationsSubmitted
        return reminingConfirmations > 0 ? .labelTertiary : .success
    }

    private func applyStrikethrough(_ label: UILabel, enabled: Bool) {
        // When `attributedText` is set, `label.text` can be nil, which would prevent us from
        // clearing a previous strike-through on reused cells. Always rebuild from the current
        // rendered string.
        let text = label.attributedText?.string ?? label.text ?? ""
        // Avoid allocating attributed strings for truly empty labels.
        if text.isEmpty {
            label.attributedText = nil
            label.text = ""
            return
        }
        var attributes: [NSAttributedString.Key: Any] = [:]
        if let font = label.font {
            attributes[.font] = font
        }
        attributes[.foregroundColor] = label.textColor as Any
        if enabled {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        label.attributedText = NSAttributedString(string: text, attributes: attributes)
    }
}
