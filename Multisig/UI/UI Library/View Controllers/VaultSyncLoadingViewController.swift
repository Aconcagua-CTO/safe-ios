//
//  VaultSyncLoadingViewController.swift
//  Multisig
//
//  Created on [Date]
//  Copyright © 2024 Gnosis Ltd. All rights reserved.
//

import UIKit

class VaultSyncLoadingViewController: UIViewController {
    private let message: String
    private var messageLabel: UILabel!
    private var fadeAnimation: UIViewPropertyAnimator?
    
    init(message: String) {
        self.message = message
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        startFadeAnimation()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopFadeAnimation()
    }
    
    private func setupUI() {
        view.backgroundColor = .backgroundPrimary
        
        messageLabel = UILabel()
        messageLabel.text = message
        messageLabel.textAlignment = .center
        messageLabel.setStyle(.title3)
        messageLabel.textColor = .labelPrimary
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(messageLabel)
        NSLayoutConstraint.activate([
            messageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            messageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])
    }
    
    private func startFadeAnimation() {
        guard messageLabel != nil else { return }
        
        stopFadeAnimation()
        
        // Start with full opacity
        messageLabel.alpha = 1.0
        
        // Create repeating fade animation
        fadeAnimation = UIViewPropertyAnimator(duration: 1.5, curve: .easeInOut) {
            self.messageLabel.alpha = 0.3
        }
        
        fadeAnimation?.addCompletion { [weak self] position in
            guard let self = self, position == .end else { return }
            // Reverse the animation
            self.messageLabel.alpha = 0.3
            let reverseAnimator = UIViewPropertyAnimator(duration: 1.5, curve: .easeInOut) {
                self.messageLabel.alpha = 1.0
            }
            reverseAnimator.addCompletion { [weak self] _ in
                self?.startFadeAnimation() // Loop the animation
            }
            reverseAnimator.startAnimation()
        }
        
        fadeAnimation?.startAnimation()
    }
    
    private func stopFadeAnimation() {
        fadeAnimation?.stopAnimation(true)
        fadeAnimation?.finishAnimation(at: .current)
        fadeAnimation = nil
    }
}

