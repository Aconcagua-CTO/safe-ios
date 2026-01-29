//
//  ComingSoonViewController.swift
//  Multisig
//
//  Created on 2026-01-08.
//

import UIKit

class ComingSoonViewController: UIViewController {
    private let screenTitle: String?

    init(title: String? = nil) {
        self.screenTitle = title
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        self.screenTitle = nil
        super.init(coder: coder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .backgroundPrimary
        
        // Create label with "Coming soon!" text
        let label = GSLabel()
        label.text = NSLocalizedString("ui_coming_soon_title", comment: "Placeholder title for screens that are not implemented yet")
        label.style = .headline
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(label)
        
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        
        // Set navigation title if needed
        title = screenTitle ?? ""
    }
}
