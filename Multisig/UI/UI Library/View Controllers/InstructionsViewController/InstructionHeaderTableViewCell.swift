//
//  InstructionHeaderTableViewCell.swift
//  Multisig
//
//  Created by Dirk Jäckel on 22.02.22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import UIKit

/// Hosts the header image in a square `clipHostView` so circular masking is always a true circle (not an oval).
class InstructionHeaderTableViewCell: UITableViewCell {

    @IBOutlet private weak var clipHostView: UIView!
    @IBOutlet private weak var headerImageView: UIImageView!

    private var hostLayoutConstraints: [NSLayoutConstraint] = []

    override func awakeFromNib() {
        super.awakeFromNib()
        clipHostView.backgroundColor = .clear
        headerImageView.backgroundColor = .clear
        headerImageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        headerImageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        headerImageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        headerImageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        NSLayoutConstraint.deactivate(hostLayoutConstraints)
        hostLayoutConstraints.removeAll()
        headerImageView.image = nil
        clipHostView.layer.cornerRadius = 0
        if #available(iOS 13.0, *) {
            clipHostView.layer.cornerCurve = .continuous
        }
    }

    func configure(imageName: String, circularClip: Bool, circularDiameter: CGFloat = 141) {
        NSLayoutConstraint.deactivate(hostLayoutConstraints)
        hostLayoutConstraints.removeAll()

        headerImageView.image = UIImage(named: imageName)?.withRenderingMode(.alwaysOriginal)

        if circularClip {
            let d = max(1, circularDiameter)
            headerImageView.contentMode = .scaleAspectFill
            clipHostView.clipsToBounds = true
            clipHostView.layer.cornerRadius = d / 2
            if #available(iOS 13.0, *) {
                clipHostView.layer.cornerCurve = .circular
            }
            hostLayoutConstraints = [
                clipHostView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                clipHostView.widthAnchor.constraint(equalToConstant: d),
                clipHostView.heightAnchor.constraint(equalToConstant: d),
                clipHostView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
                contentView.bottomAnchor.constraint(equalTo: clipHostView.bottomAnchor, constant: 16),
            ]
        } else {
            headerImageView.contentMode = .scaleAspectFit
            clipHostView.clipsToBounds = true
            clipHostView.layer.cornerRadius = 0
            if #available(iOS 13.0, *) {
                clipHostView.layer.cornerCurve = .continuous
            }
            hostLayoutConstraints = [
                clipHostView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
                clipHostView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
                clipHostView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
                clipHostView.heightAnchor.constraint(equalToConstant: 70),
                contentView.bottomAnchor.constraint(equalTo: clipHostView.bottomAnchor, constant: 16),
            ]
        }
        NSLayoutConstraint.activate(hostLayoutConstraints)
    }
}
