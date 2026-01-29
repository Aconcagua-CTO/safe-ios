//
//  SafeDeploymentFinishedViewController.swift
//  Multisig
//
//  Created by Vitaly on 23.02.22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import UIKit
import Lottie

class SafeDeploymentFinishedViewController: UIViewController {

    @IBOutlet weak var statusImage: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var descriptionLabel: UILabel!
    @IBOutlet weak var actionButton: UIButton!
    @IBOutlet weak var linkButton: UIButton!
    @IBOutlet weak var animationView: LottieAnimationView!
    @IBOutlet weak var labelContainer: UIStackView!

    enum Mode {
        case success
        case failure
    }
    
    private var mode: Mode = .success
    private var chain: Chain!
    private var txHash: String?
    private var safe: Safe?
    
    var onRetry: () -> Void = {}
    var onClose: () -> Void = {}
    
    convenience init(mode: Mode, chain: Chain, txHash: String?, safe: Safe? = nil) {
        self.init(nibName: nil, bundle: nil)
        self.mode = mode
        self.chain = chain
        self.txHash = txHash
        self.safe = safe
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        titleLabel.setStyle(.title3)
        descriptionLabel.setStyle(.body)

        switch mode {
        case .success:
            statusImage.isHidden = true
            animationView.isHidden = false
            animationView.animation = LottieAnimation.named(isDarkMode ? "successAnimationDark" : "successAnimation",
                                                      animationCache: nil)
            animationView.contentMode = .scaleAspectFit
            animationView.backgroundBehavior = .pauseAndRestore
            animationView.play()

            titleLabel.text = NSLocalizedString("ui_safe_account_ready_title", comment: "Safe account ready title")
            let chainName = chain.name ?? NSLocalizedString("ui_blockchain_generic_name", comment: "Generic blockchain name")
            descriptionLabel.text = String(format: NSLocalizedString("ui_safe_account_ready_description_format", comment: "Safe account ready description"),
                                           chainName)
            actionButton.setText(NSLocalizedString("ui_safe_start_using_title", comment: "Start using Safe action"), .filled)
            linkButton.isHidden = true

        case .failure:
            statusImage.isHidden = false
            animationView.isHidden = true
            statusImage.image = UIImage(named: "ico-safe-deployment-failure")
            titleLabel.text = NSLocalizedString("ui_safe_account_not_created_title", comment: "Safe account not created title")
            descriptionLabel.text = NSLocalizedString("ui_safe_account_not_created_description", comment: "Safe account not created description")
            
            actionButton.setText(NSLocalizedString("button_retry", comment: "Retry button title"), .filled)
            linkButton.setText(NSLocalizedString("ui_safe_view_on_block_explorer_title", comment: "View on block explorer title"), .plain)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        onClose()
    }
    
    static func present(
        presenter: UIViewController,
        mode: Mode,
        chain: Chain,
        txHash: String? ,
        safe: Safe? = nil,
        onClose: @escaping () -> Void,
        onRetry: @escaping () -> Void
    ) {
        let finishedVC = SafeDeploymentFinishedViewController(mode: mode, chain: chain, txHash: txHash, safe: safe)
        finishedVC.onRetry = onRetry
        finishedVC.onClose = onClose
        let vc = ViewControllerFactory.pageSheet(viewController: finishedVC, halfScreen: true)
        presenter.present(vc, animated: true)
    }
    
    @IBAction func didTapActionButton(_ sender: Any) {
        
        switch mode {
            
        case .success:
            // select deployed safe
            if let safe = safe {
                safe.select()
            }

            dismiss(animated: true, completion: nil)
            
        case .failure:
            // retry safe deployment transaction
            dismiss(animated: true, completion: nil)
            onRetry()
        }
    }
    
    @IBAction func didTapViewOnBlockExplorer(_ sender: Any) {
        
        Tracker.trackEvent(.createSafeViewTxOnEtherscan)

        guard let txHash = txHash else {
            return
        }
        
        let url = chain.browserURL(txHash: txHash)
        openInSafari(url)
    }
}
