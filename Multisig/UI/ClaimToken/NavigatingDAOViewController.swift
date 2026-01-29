//
//  NavigatingDAOViewController.swift
//  Multisig
//
//  Created by Dirk Jäckel on 06.09.22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import UIKit

class NavigatingDAOViewController: UIViewController {

    @IBOutlet weak var introductionParagraph: UILabel!
    @IBOutlet weak var screenTitle: UILabel!
    @IBOutlet weak var checklistTitle: UILabel!
    @IBOutlet weak var nextButton: UIButton!

    @IBOutlet weak var discussItemLabel: UILabel!
    @IBOutlet weak var proposeItemLabel: UILabel!
    @IBOutlet weak var governItemLabel: UILabel!
    @IBOutlet weak var chatItemLabel: UILabel!
    @IBOutlet weak var subTitle: UILabel!

    private var onNext: (() -> ())?
    private var completion: (() -> Void)?

    convenience init(completion: @escaping () -> ()) {
        self.init(namedClass: NavigatingDAOViewController.self)
        self.completion = completion
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Tracker.trackEvent(.screenClaimDao)

        ViewControllerFactory.removeNavigationBarBorder(self)
        navigationItem.largeTitleDisplayMode = .never

        screenTitle.setStyle(.title2)

        introductionParagraph.setStyle(.body)

        checklistTitle.setStyle(.headline)

        nextButton.setText(NSLocalizedString("ui_claim_dao_start_action", comment: "Start claiming action"),
                           .filled)

        discussItemLabel.hyperLinkLabel(NSLocalizedString("ui_claim_dao_discuss_prefix", comment: "DAO discuss prefix"),
                prefixStyle: .body,
                linkText: NSLocalizedString("ui_claim_forum_link", comment: "Forum link title"),
                linkIcon: nil,
                underlined: false,
                postfixText: NSLocalizedString("ui_claim_dao_discuss_postfix", comment: "DAO discuss postfix")
        )
        openUrlOnTap(link: .discuss, label: discussItemLabel)

        proposeItemLabel.hyperLinkLabel(NSLocalizedString("ui_claim_dao_propose_prefix", comment: "DAO propose prefix"),
                prefixStyle: .body,
                linkText: NSLocalizedString("ui_claim_dao_governance_process_link", comment: "DAO governance process link"),
                linkIcon: nil,
                underlined: false,
                postfixText: NSLocalizedString("ui_claim_dao_propose_postfix", comment: "DAO propose postfix")
        )
        openUrlOnTap(link: .propose, label: proposeItemLabel)

        let governText = NSLocalizedString("ui_claim_dao_govern_text", comment: "DAO govern text")
        governItemLabel.setStyle(.body)

        chatItemLabel.setStyle(.body)
        chatItemLabel.hyperLinkLabel(NSLocalizedString("ui_claim_dao_chat_prefix", comment: "DAO chat prefix"),
                prefixStyle: .body,
                linkText: NSLocalizedString("ui_claim_dao_chat_link", comment: "DAO chat link"),
                linkIcon: nil,
                underlined: false,
                postfixText: NSLocalizedString("ui_claim_dao_chat_postfix", comment: "DAO chat postfix")
        )
        openUrlOnTap(link: .chat, label: chatItemLabel)

        subTitle.setStyle(.headline)
        subTitle.textAlignment = .center
    }

    @IBAction func nextClicked(_ sender: Any) {
        Tracker.trackEvent(.userClaimDaoStart)
        completion?()
    }

    func openUrlOnTap(link: link, label: UILabel) {
        var tapRecognizer: UITapGestureRecognizer
        switch link {
        case .discuss: tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(discussTap(sender:)))
        case .propose: tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(proposeTap(sender:)))
        case .chat:  tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(chatTap(sender:)))
        }
        label.addGestureRecognizer(tapRecognizer)
    }

    @objc
    func discussTap(sender: UITapGestureRecognizer) {
        openInSafari(App.configuration.claim.discussURL)
    }

    @objc
    func proposeTap(sender: UITapGestureRecognizer) {
        openInSafari(App.configuration.claim.proposeURL)
    }

    @objc
    func chatTap(sender: UITapGestureRecognizer) {
        openInSafari(App.configuration.claim.chatURL)
    }

    enum link {
        case discuss, propose, chat
    }
}

