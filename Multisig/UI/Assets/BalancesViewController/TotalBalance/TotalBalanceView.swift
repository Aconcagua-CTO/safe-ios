//
//  TotalBalanceView.swift
//  Multisig
//
//  Created by Vitaly Katz on 13.12.21.
//  Copyright © 2021 Gnosis Ltd. All rights reserved.
//

import UIKit
import SkeletonView

class TotalBalanceView: UINibView {
    @IBOutlet weak var ribbonView: RibbonView!
    @IBOutlet weak var amountLabel: UILabel!
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var receiveButton: UIButton!
    @IBOutlet weak var buyButton: UIButton?
    @IBOutlet weak var tokenBanner: SafeTokenBanner!
    @IBOutlet weak var relayInfoBanner: RelayInfoBanner!

    var onSendClicked: (() -> Void)?
    var onReceivedClicked: (() -> Void)?
    var onBuyClicked: (() -> Void)?

    var amount: String? {
        didSet {
            amountLabel.text = amount
        }
    }
    
    var loading: Bool = false {
        didSet {
            if (loading) {
                amountLabel.showSkeleton()
            } else {
                amountLabel.hideSkeleton()
            }
        }
    }
    
    var sendEnabled: Bool = false {
        didSet {
            sendButton.isEnabled = sendEnabled
        }
    }

    var buyEnabled: Bool = false {
        didSet {
            buyButton?.isHidden = true
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Configure ribbon to show "Balance"
        ribbonView.text = "Balance"
        ribbonView.textColor = .labelPrimary
        ribbonView.backgroundColor = .clear
        ribbonView.show()
        amountLabel.skeletonTextLineHeight = .relativeToConstraints
        amountLabel.setStyle(.title1Medium)
        sendButton.setText("Retirar", .filled)
        sendButton.setImage(UIImage(named: "ico-arrow-down"), for: .normal)
        sendButton.tintColor = UIColor.primaryInverted
        receiveButton.setText("Ingresar", .filled)
        receiveButton.setImage(rotatedUpArrow(), for: .normal)
        receiveButton.tintColor = UIColor.primaryInverted
        receiveButton.isEnabled = true
        buyButton?.isHidden = true
    }

    /// Generates an upward arrow by rotating the existing downward arrow asset 180 degrees.
    private func rotatedUpArrow() -> UIImage? {
        guard let image = UIImage(named: "ico-arrow-down") else { return nil }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        let rotated = renderer.image { context in
            context.cgContext.translateBy(x: image.size.width / 2, y: image.size.height / 2)
            context.cgContext.rotate(by: .pi)
            context.cgContext.translateBy(x: -image.size.width / 2, y: -image.size.height / 2)
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        return rotated.withRenderingMode(image.renderingMode)
    }
    
    @IBAction func sendButtonClicked(_ sender: Any) {
        onSendClicked?()
    }
    
    @IBAction func receiveButtonClicked(_ sender: Any) {
        onReceivedClicked?()
    }

    @IBAction func buyButtonClicked(_ sender: Any) {
        onBuyClicked?()
    }
}
