//
//  ComingSoonViewController.swift
//  Multisig
//
//  Created on 20.01.26.
//  Copyright © 2026 Gnosis Ltd. All rights reserved.
//

import UIKit

class ComingSoonViewController: UIViewController {
    
    private let messageLabel: UILabel = {
        let label = UILabel()
        label.text = "Coming Soon!"
        label.font = .systemFont(ofSize: 24, weight: .bold)
        label.textAlignment = .center
        label.textColor = .labelPrimary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .backgroundPrimary
        
        view.addSubview(messageLabel)
        
        NSLayoutConstraint.activate([
            messageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}
