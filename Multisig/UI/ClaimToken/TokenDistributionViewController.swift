//
//  TokenDistributionViewController.swift
//  Multisig
//
//  Created by Mouaz on 9/5/22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import UIKit

class TokenDistributionViewController: UIViewController {

    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var descriptionLabel: UILabel!
    @IBOutlet private weak var nextButton: UIButton!
    @IBOutlet weak var distributionView: BorderedCheveronButton!

    private var onNext: (() -> ())?

    convenience init(onNext: @escaping () -> ()) {
        self.init(namedClass: TokenDistributionViewController.self)
        self.onNext = onNext
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Tracker.trackEvent(.screenClaimDistr)

        ViewControllerFactory.removeNavigationBarBorder(self)
        navigationItem.largeTitleDisplayMode = .never
        distributionView.set(NSLocalizedString("ui_claim_distribution_details_title", comment: "Distribution details title")) { [unowned self] in
            Tracker.trackEvent(.userClaimDistrDetails)

            let content: [(title: String?, description: String?)] = [
                (title: NSLocalizedString("ui_claim_distribution_community_title", comment: "Distribution community title"),
                 description: NSLocalizedString("ui_claim_distribution_community_desc", comment: "Distribution community description")),
                (title: NSLocalizedString("ui_claim_distribution_core_title", comment: "Distribution core title"),
                 description: NSLocalizedString("ui_claim_distribution_core_desc", comment: "Distribution core description")),
                (title: NSLocalizedString("ui_claim_distribution_foundation_title", comment: "Distribution foundation title"),
                 description: NSLocalizedString("ui_claim_distribution_foundation_desc", comment: "Distribution foundation description")),
                (title: NSLocalizedString("ui_claim_distribution_ecosystem_title", comment: "Distribution ecosystem title"),
                 description: NSLocalizedString("ui_claim_distribution_ecosystem_desc", comment: "Distribution ecosystem description")),
                (title: NSLocalizedString("ui_claim_distribution_user_title", comment: "Distribution user title"),
                 description: NSLocalizedString("ui_claim_distribution_user_desc", comment: "Distribution user description"))]
            let vc = ViewControllerFactory.modal(viewController: DetailedInfoListViewController(title: NSLocalizedString("ui_claim_distribution_details_title", comment: "Distribution details title"),
                                                                                                content: content,
                                                                                                trackingEvent: .screenClaimDistrDetail))
            present(vc, animated: true)
        }
        titleLabel.setStyle(.title2)
        descriptionLabel.setStyle(.body)
        nextButton.setText(NSLocalizedString("button_next", comment: "Next button title"), .filled)
    }

    @IBAction func didTapNext(_ sender: Any) {
        Tracker.trackEvent(.userClaimDistrNext)
        onNext?()
    }
}
