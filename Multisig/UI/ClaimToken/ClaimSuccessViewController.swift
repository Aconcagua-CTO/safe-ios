//
//  ClaimSuccessViewController.swift
//  Multisig
//
//  Created by Vitaly on 01.08.22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import UIKit
import SwiftCryptoTokenFormatter
import Lottie
import Solidity

class ClaimSuccessViewController: UIViewController {

    @IBOutlet weak var okButton: UIButton!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var textLabel: UILabel!
    @IBOutlet weak var askLabel: UILabel!
    @IBOutlet weak var tweetBox: TweetBox!
    @IBOutlet weak var animationView: LottieAnimationView!
    @IBOutlet weak var shareButton: UIButton!

    var amount: Sol.UInt128!
    var guardian: Guardian?
    var hasChangedDelegate: Bool = true

    var onOk: (() -> ())?
    var onShare: (() -> ())?

    override func viewDidLoad() {
        super.viewDidLoad()
        Tracker.trackEvent(.screenClaimSuccess)

        ViewControllerFactory.addCloseButton(self)
        ViewControllerFactory.makeTransparentNavigationBar(self)
        navigationItem.largeTitleDisplayMode = .never

        titleLabel.text = NSLocalizedString("ui_claim_success_title", comment: "Claim success title")
        titleLabel.setStyle(.title1)

        askLabel.text = NSLocalizedString("ui_claim_success_share_prompt", comment: "Claim share prompt")
        askLabel.setStyle(.headline)

        let displayAmount = TokenFormatter().string(from: BigDecimal(Int256(amount!.big()), 18)) + " SAFE"

        let text = String(format: NSLocalizedString("ui_claim_success_body_format", comment: "Claim success body"),
                          displayAmount)

        textLabel.attributedText = text.highlightRange(
            originalStyle: .body,
            highlightStyle: .bodyPrimary,
            textToHighlight: displayAmount
        )

        tweetBox.setTweet(text: tweetText, highlights: ["@Safe"])

        okButton.setText(NSLocalizedString("button_done", comment: "Done button title"), .filled)

        shareButton.setText(NSLocalizedString("ui_claim_share_transaction_action", comment: "Share transaction action"),
                            .primary)
        shareButton.setImage(UIImage(named: "ico-share")?.withTintColor(.primary), for: .normal)
        shareButton.imageEdgeInsets.right = 16
        animationView.animation = LottieAnimation.named(isDarkMode ? "successAnimationDark" : "successAnimation",
                                                  animationCache: nil)
        animationView.contentMode = .scaleAspectFit
        animationView.backgroundBehavior = .pauseAndRestore
        animationView.play()
    }

    private var tweetText: String {
        let text: String

        if hasChangedDelegate, let guardian = guardian, let ens = guardian.ens {
            text = String(format: NSLocalizedString("ui_claim_tweet_delegate_format", comment: "Claim tweet with delegate"),
                          ens)
        } else if hasChangedDelegate, guardian != nil {
            text = NSLocalizedString("ui_claim_tweet_delegate_no_ens", comment: "Claim tweet without ENS")
        } else {
            text = NSLocalizedString("ui_claim_tweet_claim_only", comment: "Claim tweet without delegation")
        }

        return text
    }

    @IBAction func didTapTweetButton(_ sender: Any) {
        Tracker.trackEvent(.userClaimSuccessTweet)

        let shareString = "https://twitter.com/intent/tweet?text=\(tweetText)"
        let escapedShareString = shareString.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed)!
        let url = URL(string: escapedShareString)
        UIApplication.shared.open(url!, options: [:], completionHandler: nil)
    }

    @IBAction func didTapShare(_ sender: Any) {
        Tracker.trackEvent(.userClaimSuccessShare)
        onShare?()
    }

    @IBAction func didTapOkButton(_ sender: Any) {
        Tracker.trackEvent(.userClaimSuccessDone)
        onOk?()
    }

    override func closeModal() {
        Tracker.trackEvent(.userClaimSuccessClose)
        super.closeModal()
    }
}
