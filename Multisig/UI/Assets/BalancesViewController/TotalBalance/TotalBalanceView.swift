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
    private let vaultSyncLoaderView = VaultIconFadeView(iconSize: 24)

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
            updateLoadingPresentation()
        }
    }

    var vaultSyncing: Bool = false {
        didSet {
            #if DEBUG
            LogService.shared.debug("[TotalBalanceView] vaultSyncing=\(vaultSyncing)")
            #endif
            updateLoadingPresentation()
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
        sendButton.setText(NSLocalizedString("ui_balance_withdraw_action", comment: "Withdraw action"), .filled)
        sendButton.setImage(UIImage(named: "ico-arrow-down"), for: .normal)
        sendButton.tintColor = UIColor.primaryInverted
        receiveButton.setText(NSLocalizedString("ui_balance_deposit_action", comment: "Deposit action"), .filled)
        receiveButton.setImage(rotatedUpArrow(), for: .normal)
        receiveButton.tintColor = UIColor.primaryInverted
        receiveButton.isEnabled = true
        buyButton?.isHidden = true
        setupVaultSyncLoaderView()
        updateLoadingPresentation()
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

    private func setupVaultSyncLoaderView() {
        guard let containerView = amountLabel.superview else { return }
        vaultSyncLoaderView.translatesAutoresizingMaskIntoConstraints = false
        vaultSyncLoaderView.isHidden = true
        containerView.addSubview(vaultSyncLoaderView)
        NSLayoutConstraint.activate([
            vaultSyncLoaderView.centerXAnchor.constraint(equalTo: amountLabel.centerXAnchor),
            vaultSyncLoaderView.centerYAnchor.constraint(equalTo: amountLabel.centerYAnchor),
            vaultSyncLoaderView.widthAnchor.constraint(equalTo: amountLabel.widthAnchor),
            vaultSyncLoaderView.heightAnchor.constraint(equalTo: amountLabel.heightAnchor),
        ])
    }

    private func updateLoadingPresentation() {
        if vaultSyncing {
            amountLabel.hideSkeleton()
            vaultSyncLoaderView.isHidden = false
            vaultSyncLoaderView.startAnimating()
            #if DEBUG
            LogService.shared.debug("[TotalBalanceView] Showing vault icon fade loader")
            #endif
            return
        }

        vaultSyncLoaderView.stopAnimating()
        vaultSyncLoaderView.isHidden = true

        if loading {
            amountLabel.showSkeleton()
            #if DEBUG
            LogService.shared.debug("[TotalBalanceView] Showing default skeleton loader")
            #endif
        } else {
            amountLabel.hideSkeleton()
        }
    }
}
