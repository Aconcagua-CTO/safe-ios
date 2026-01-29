//
//  DetailStatusCell.swift
//  Multisig
//
//  Created by Moaaz on 12/3/20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import UIKit

class DetailStatusCell: UITableViewCell {
    @IBOutlet private weak var iconImageView: UIImageView!
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var appendixLabel: UILabel!
    @IBOutlet private weak var statusIconImageView: UIImageView!
    @IBOutlet private weak var statusLabel: UILabel!
    @IBOutlet private weak var bottomStackView: UIStackView!
    @IBOutlet private weak var tagView: TagView!

    override func awakeFromNib() {
        super.awakeFromNib()
        titleLabel.setStyle(.headline)
        appendixLabel.setStyle(.headline)
        statusLabel.setStyle(.headline)
    }

    func setTitle(_ title: String) {
        titleLabel.text = title
    }

    func setIcon(_ icon: UIImage?) {
        iconImageView.image = icon
        iconImageView.contentMode = .center
    }

    func set(contractImageUrl: URL? = nil, contractAddress: AddressString) {
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.setCircleImage(url: contractImageUrl, address: contractAddress.address)

    }

    func set(imageUrl: URL? = nil, placeholder: UIImage?) {
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.setCircleShapeImage(url: imageUrl, placeholder: placeholder)
    }

    func setStatus(_ status: SCGModels.TxStatus, isReplaced: Bool = false) {
        let statusText = isReplaced
            ? NSLocalizedString("ui_tx_status_replaced", comment: "Transaction replaced status")
            : localizedStatusTitle(for: status)
        statusLabel.text = statusText
        appendixLabel.text = statusText

        let isWaiting = isReplaced ? false : status.isWaiting
        appendixLabel.isHidden = isWaiting
        bottomStackView.isHidden = !isWaiting

        let color = isReplaced ? UIColor.labelSecondary : statusColor(status: status)
        statusLabel.textColor = color
        appendixLabel.textColor = color

        applyStrikethrough(titleLabel, enabled: isReplaced)
    }

    private func localizedStatusTitle(for status: SCGModels.TxStatus) -> String {
        switch status {
        case .awaitingExecution, .awaitingConfirmations, .awaitingYourConfirmation, .pending:
            return NSLocalizedString("ui_tx_status_pending", comment: "Transaction pending status")
        case .failed:
            return NSLocalizedString("ui_tx_status_failed", comment: "Transaction failed status")
        case .cancelled:
            return NSLocalizedString("ui_tx_status_cancelled", comment: "Transaction cancelled status")
        case .success:
            return NSLocalizedString("ui_tx_status_executed", comment: "Transaction executed status")
        }
    }

    func statusColor(status: SCGModels.TxStatus) -> UIColor {
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

    func set(tag: String) {
        tagView.isHidden = tag.isEmpty
        tagView.set(title: tag)
    }

    private func applyStrikethrough(_ label: UILabel, enabled: Bool) {
        // When `attributedText` is set, `label.text` can be nil. Always rebuild from the
        // current rendered string to ensure we clear strike-through on reused views.
        let text = label.attributedText?.string ?? label.text ?? ""
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

extension SCGModels.TxStatus {
    static let queueStatuses = [awaitingConfirmations, .awaitingExecution, .awaitingYourConfirmation, .pending]
    static let historyStatuses = [success, .failed, .cancelled]
    static let failedStatuses = [failed, .cancelled]

    var isInQueue: Bool {
        Self.queueStatuses.contains(self)
    }

    var isInHistory: Bool {
        Self.historyStatuses.contains(self)
    }

    var isWaiting: Bool {
        Self.queueStatuses.contains(self)
    }

    var isFailed: Bool {
        Self.failedStatuses.contains(self)
    }

    var title: String {
        switch self {
        case .awaitingExecution:
            return "Needs execution"
        case .awaitingConfirmations:
            return "Needs confirmations"
        case .awaitingYourConfirmation:
            return "Needs your confirmation"
        case .pending:
             return "Pending"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        case .success:
            return "Success"
        }
    }
}
