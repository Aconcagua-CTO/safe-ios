//
//  DetailTransferInfoCell.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 03.12.20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import UIKit

class DetailTransferInfoCell: UITableViewCell {
    @IBOutlet private weak var stackView: UIStackView!
    private var tokenInfoView: TokenInfoView!
    private var addressInfoView: AddressInfoView!
    private var arrowView: DetailArrowPiece!

    override func awakeFromNib() {
        super.awakeFromNib()
        tokenInfoView = TokenInfoView(frame: stackView.bounds)
        addressInfoView = AddressInfoView(frame: stackView.bounds)
        arrowView = DetailArrowPiece(frame: stackView.bounds)

        // These views are laid out via Auto Layout (inside a UIStackView).
        tokenInfoView.translatesAutoresizingMaskIntoConstraints = false
        addressInfoView.translatesAutoresizingMaskIntoConstraints = false
        arrowView.translatesAutoresizingMaskIntoConstraints = false

        // Because we created the views programmatically, we set the
        // heights in code:
        let tokenHeight = tokenInfoView.heightAnchor.constraint(equalToConstant: 44)
        let addressHeight = addressInfoView.heightAnchor.constraint(equalToConstant: 44)
        let arrowHeight = arrowView.heightAnchor.constraint(equalToConstant: 24)
        // Allow UITableView's calculated row height to win (prevents constraint-breaking / flicker).
        tokenHeight.priority = UILayoutPriority(999)
        addressHeight.priority = UILayoutPriority(999)
        arrowHeight.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([tokenHeight, addressHeight, arrowHeight])
    }

    func setAddress(_ address: Address, label: String?, imageUri: URL?, browseURL: URL?, prefix: String?) {
        addressInfoView.setAddress(address, label: label, imageUri: imageUri,browseURL: browseURL, prefix: prefix)
    }

    func setToken(text: String, style: GNOTextStyle) {
        tokenInfoView.setText(text, style: style)
    }

    func setToken(image: UIImage?) {
        tokenInfoView.setImage(image)
    }

    func setToken(image url: URL?, placeholder: UIImage? = nil) {
        tokenInfoView.setImage(url, placeholder: placeholder)
    }

    func setToken(alpha: CGFloat) {
        tokenInfoView.alpha = alpha
    }

    func setDetail(_ text: String?) {
        tokenInfoView.setDetail(text)
    }

    func setOutgoing(_ isOutgoing: Bool) {
        var views: [UIView] = [addressInfoView, arrowView, tokenInfoView]
        if isOutgoing {
            views.reverse()
        }
        for view in stackView.arrangedSubviews {
            view.removeFromSuperview()
        }
        for view in views {
            stackView.addArrangedSubview(view)
        }
    }

}
