//
//  FinalStepInstructionTableViewCell.swift
//  Multisig
//
//  Created by Dirk Jäckel on 22.02.22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import UIKit

class FinalStepInstructionTableViewCell: UITableViewCell {

    @IBOutlet weak var cellLabel: UILabel!
    @IBOutlet weak var checkmarkImageView: UIImageView!
    @IBOutlet weak var labelLeadingToCheckmarkConstraint: NSLayoutConstraint!

    private var labelLeadingToContentConstraint: NSLayoutConstraint?

    override func awakeFromNib() {
        super.awakeFromNib()
        cellLabel.setStyle(.headline)
        cellLabel.numberOfLines = 0
        cellLabel.lineBreakMode = .byWordWrapping

        labelLeadingToContentConstraint = cellLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
        labelLeadingToContentConstraint?.isActive = false
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        configure(title: "", showsLeadingCheckmark: true)
    }

    func configure(title: String, showsLeadingCheckmark: Bool) {
        cellLabel.text = title
        checkmarkImageView.isHidden = !showsLeadingCheckmark
        labelLeadingToCheckmarkConstraint.isActive = showsLeadingCheckmark
        labelLeadingToContentConstraint?.isActive = !showsLeadingCheckmark
    }
}
