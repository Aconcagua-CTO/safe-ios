//
//  StepInstructionTableViewCell.swift
//  Multisig
//
//  Created by Dirk Jäckel on 22.02.22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import UIKit

class StepInstructionTableViewCell: UITableViewCell {
    @IBOutlet weak var circleFillImageView: UIImageView!
    @IBOutlet weak var leadingCheckmarkImageView: UIImageView!
    @IBOutlet weak var circleLabel: UILabel!
    @IBOutlet weak var headerLabel: UILabel!
    @IBOutlet weak var descriptionLabel: UILabel!
    @IBOutlet weak var verticalBarView: UIImageView!
    @IBOutlet weak var contentViewTopPaddingConstraint: NSLayoutConstraint!

    override func awakeFromNib() {
        super.awakeFromNib()
        setStyles()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        descriptionLabel.isHidden = false
        setStyles()
    }

    func apply(leading: InstructionStepLeading) {
        switch leading {
        case .number(let digit):
            leadingCheckmarkImageView.isHidden = true
            circleFillImageView.isHidden = false
            circleLabel.isHidden = false
            circleLabel.text = digit
        case .greenCheckmark:
            leadingCheckmarkImageView.isHidden = false
            circleFillImageView.isHidden = true
            circleLabel.isHidden = true
        }
    }

    func setStyles(circleStyle: GNOTextStyle = .subheadlineSecondary,
                   headerStyle: GNOTextStyle = .headline,
                   descriptionStyle: GNOTextStyle = .callout,
                   verticalBarViewHidden: Bool = false,
                   topPadding: CGFloat = 0) {
        verticalBarView.isHidden = verticalBarViewHidden
        descriptionLabel.setStyle(descriptionStyle)
        circleLabel.setStyle(circleStyle)
        headerLabel.setStyle(headerStyle)
        contentViewTopPaddingConstraint.constant = topPadding
    }
}
