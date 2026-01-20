//
//  ComingSoonViewController.swift
//  Multisig
//
//  Created on 2026-01-08.
//

import UIKit

class ComingSoonViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .backgroundPrimary
        
        // Create label with "Coming soon!" text
        let label = GSLabel()
        label.text = "Coming soon!"
        label.style = .headline
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(label)
        
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        
        // Set navigation title if needed
        title = ""
    }
}
