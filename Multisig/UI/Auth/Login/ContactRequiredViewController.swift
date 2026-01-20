//
//  ContactRequiredViewController.swift
//  Multisig
//
//  Created on 2026-01-16.
//

import UIKit

final class ContactRequiredViewController: UIViewController {
    private let message: String
    
    init(message: String) {
        self.message = message
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .backgroundPrimary
        
        let messageButton = UIButton(type: .system)
        messageButton.translatesAutoresizingMaskIntoConstraints = false
        messageButton.titleLabel?.numberOfLines = 0
        messageButton.titleLabel?.textAlignment = .center
        messageButton.contentHorizontalAlignment = .center
        messageButton.addTarget(self, action: #selector(openWhatsApp), for: .touchUpInside)
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 17, weight: .regular),
            .foregroundColor: UIColor.primary,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        let attributedTitle = NSAttributedString(string: message, attributes: attributes)
        messageButton.setAttributedTitle(attributedTitle, for: .normal)
        
        view.addSubview(messageButton)
        
        NSLayoutConstraint.activate([
            messageButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            messageButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            messageButton.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    @objc private func openWhatsApp() {
        let phoneNumber = "5491134120450"
        let message = "Consulta desde boveda.ai"
        let encodedMessage = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? message
        
        guard let url = URL(string: "https://wa.me/\(phoneNumber)?text=\(encodedMessage)") else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}

