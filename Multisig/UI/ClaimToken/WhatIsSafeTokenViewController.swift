//
//  WhatIsSafeViewController.swift
//  Multisig
//
//  Created by Mouaz on 9/5/22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import UIKit

class WhatIsSafeTokenViewController: UIViewController {
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var descriptionLabel: UILabel!
    @IBOutlet private weak var nextButton: UIButton!
    @IBOutlet private weak var safeProtocolView: BorderedCheveronButton!
    @IBOutlet private weak var interfacesView: BorderedCheveronButton!
    @IBOutlet private weak var assetsView: BorderedCheveronButton!
    @IBOutlet private weak var tokenomicsView: BorderedCheveronButton!
    @IBOutlet private weak var tokenNonTrnasferableLabel: UILabel!

    private var onNext: (() -> ())?


    convenience init(onNext: @escaping () -> ()) {
        self.init(namedClass: WhatIsSafeTokenViewController.self)
        self.onNext = onNext
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Tracker.trackEvent(.screenClaimGov)

        ViewControllerFactory.removeNavigationBarBorder(self)

        safeProtocolView.set(NSLocalizedString("ui_claim_safe_protocol_title", comment: "Safe protocol title")) { [unowned self] in
            Tracker.trackEvent(.userClaimGovProto)

            let content: [(title: String?, description: String?)] = [
                (title: nil, description: NSLocalizedString("ui_claim_safe_protocol_description", comment: "Safe protocol description"))]
            let vc = DetailedInfoListViewController(title: NSLocalizedString("ui_claim_safe_protocol_title", comment: "Safe protocol title"), content: content)

            let viewController = ViewControllerFactory.modal(viewController: vc, halfScreen: true)
            present(viewController, animated: true)
        }

        interfacesView.set(NSLocalizedString("ui_claim_interfaces_title", comment: "Interfaces title")) { [unowned self] in
            Tracker.trackEvent(.userClaimGovInterface)

            let content: [(title: String?, description: String?)] = [
                (title: nil, description: NSLocalizedString("ui_claim_interfaces_description", comment: "Interfaces description"))]
            let vc = DetailedInfoListViewController(title: NSLocalizedString("ui_claim_interfaces_title", comment: "Interfaces title"), content: content)

            let viewController = ViewControllerFactory.modal(viewController: vc, halfScreen: true)
            present(viewController, animated: true)
        }

        assetsView.set(NSLocalizedString("ui_claim_onchain_assets_title", comment: "On-chain assets title")) { [unowned self] in
            Tracker.trackEvent(.userClaimGovAssets)

            let content: [(title: String?, description: String?)] = [
                (title: nil, description: NSLocalizedString("ui_claim_onchain_assets_description", comment: "On-chain assets description"))]
            let vc = DetailedInfoListViewController(title: NSLocalizedString("ui_claim_onchain_assets_title", comment: "On-chain assets title"), content: content)

            let viewController = ViewControllerFactory.modal(viewController: vc, halfScreen: true)
            present(viewController, animated: true)
        }

        tokenomicsView.set(NSLocalizedString("ui_claim_tokenomics_title", comment: "Tokenomics title")) { [unowned self] in
            Tracker.trackEvent(.userClaimGovToken)

            let content: [(title: String?, description: String?)] = [
                (title: nil, description: NSLocalizedString("ui_claim_tokenomics_description", comment: "Tokenomics description"))]
            let vc = DetailedInfoListViewController(title: NSLocalizedString("ui_claim_tokenomics_title", comment: "Tokenomics title"), content: content)

            let viewController = ViewControllerFactory.modal(viewController: vc, halfScreen: true)
            present(viewController, animated: true)
        }

        tokenNonTrnasferableLabel.setStyle(.callout.color(.labelSecondary))
        titleLabel.setStyle(.title2)
        descriptionLabel.setStyle(.body)
        nextButton.setText(NSLocalizedString("button_next", comment: "Next button title"), .filled)
    }

    @IBAction func didTapNext(_ sender: Any) {
        Tracker.trackEvent(.userClaimGovNext)
        onNext?()
    }
}

