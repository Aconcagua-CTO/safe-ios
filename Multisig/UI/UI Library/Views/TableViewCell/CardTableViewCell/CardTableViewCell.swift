//
//  CardTableViewCell.swift
//  Multisig
//
//  Created by Moaaz on 1/21/21.
//  Copyright © 2021 Gnosis Ltd. All rights reserved.
//

import UIKit

class CardTableViewCell: UITableViewCell, ExternalURLSource {
    enum TopIconLayout {
        case square50
        case widePasskey
        case square141
        /// Same 141×141 frame as `square141`, clipped to a circle (e.g. card photo like the legacy illustration).
        case square141Circular
    }

    private static let topHeroSize: CGFloat = 141

    @IBOutlet private weak var bodyLabel: UILabel!
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var iconImageView: UIImageView!
    @IBOutlet private weak var middleIconImageView: UIImageView!
    @IBOutlet weak var linkLabel: UILabel!
    @IBOutlet weak var linkButton: UIButton!

    private(set) var url: URL?

    private var topIconSquare50Constraints: [NSLayoutConstraint] = []
    private var topIconWideConstraints: [NSLayoutConstraint] = []
    private var topIconSquare141Constraints: [NSLayoutConstraint] = []
    private var didSetupTopIconLayouts = false

    @IBAction func openUrl(_ sender: Any) {
        openExternalURL()
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        titleLabel.setStyle(.headline)
        bodyLabel.setStyle(.body)
        selectionStyle = .none
        iconImageView.backgroundColor = .clear
        middleIconImageView.backgroundColor = .clear
        iconImageView.tintColor = .labelPrimary
        middleIconImageView.tintColor = .labelPrimary
        iconImageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        iconImageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        iconImageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        iconImageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        setupTopIconLayoutConstraints()
    }

    private func setupTopIconLayoutConstraints() {
        guard !didSetupTopIconLayouts else { return }
        didSetupTopIconLayouts = true

        topIconSquare50Constraints = [
            iconImageView.widthAnchor.constraint(equalToConstant: 50),
            iconImageView.heightAnchor.constraint(equalToConstant: 50),
        ]

        let h72 = iconImageView.heightAnchor.constraint(equalToConstant: 72)
        let aspect = iconImageView.widthAnchor.constraint(equalTo: iconImageView.heightAnchor, multiplier: 620.0 / 325.0)
        topIconWideConstraints = [h72, aspect]

        topIconSquare141Constraints = [
            iconImageView.widthAnchor.constraint(equalToConstant: Self.topHeroSize),
            iconImageView.heightAnchor.constraint(equalToConstant: Self.topHeroSize),
        ]

        NSLayoutConstraint.activate(topIconSquare50Constraints)
    }

    private func allTopIconConstraints() -> [NSLayoutConstraint] {
        topIconSquare50Constraints + topIconWideConstraints + topIconSquare141Constraints
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        linkLabel.isHidden = false
        linkButton.isHidden = false
        set(image: nil, middleImage: nil, topIconLayout: .square50)
    }

    func set(image: UIImage?) {
        set(image: image, middleImage: nil, topIconLayout: .square50)
    }

    func set(image: UIImage?, middleImage: UIImage?, topIconLayout layout: TopIconLayout) {
        setupTopIconLayoutConstraints()
        iconImageView.image = image
        middleIconImageView.image = middleImage
        let hasMiddle = middleImage != nil
        middleIconImageView.isHidden = !hasMiddle

        NSLayoutConstraint.deactivate(allTopIconConstraints())
        switch layout {
        case .square50:
            NSLayoutConstraint.activate(topIconSquare50Constraints)
            applyTopIconCircularPresentation(circular: false)
        case .widePasskey:
            NSLayoutConstraint.activate(topIconWideConstraints)
            applyTopIconCircularPresentation(circular: false)
        case .square141:
            NSLayoutConstraint.activate(topIconSquare141Constraints)
            applyTopIconCircularPresentation(circular: false)
        case .square141Circular:
            NSLayoutConstraint.activate(topIconSquare141Constraints)
            applyTopIconCircularPresentation(circular: true)
        }
    }

    private func applyTopIconCircularPresentation(circular: Bool) {
        if circular {
            iconImageView.layer.cornerRadius = Self.topHeroSize / 2
            if #available(iOS 13.0, *) {
                iconImageView.layer.cornerCurve = .circular
            }
            iconImageView.clipsToBounds = true
            iconImageView.contentMode = .scaleAspectFill
        } else {
            iconImageView.layer.cornerRadius = 0
            if #available(iOS 13.0, *) {
                iconImageView.layer.cornerCurve = .continuous
            }
            iconImageView.clipsToBounds = true
            iconImageView.contentMode = .scaleAspectFit
        }
    }

    func set(title: String) {
        titleLabel.text = title
    }

    func set(body: String) {
        bodyLabel.text = body
    }

    func set(linkTitle: String?, url: URL?) {
        guard let linkTitle = linkTitle,
              let url = url else {
            linkLabel.isHidden = true
            linkButton.isHidden = true
            return
        }
        linkLabel.hyperLinkLabel(linkText: linkTitle)
        self.url = url
    }
}
