//
//  ContactRequiredViewController.swift
//  Multisig
//
//  Created on 2026-01-16.
//

import UIKit
final class ContactRequiredViewController: UIViewController {
    private let message: String
    private let onBack: (() -> Void)?
    
    init(message: String, onBack: (() -> Void)? = nil) {
        self.message = message
        self.onBack = onBack
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
        
        // External link icon (square with arrow) appended to the attributed title.
        // This avoids layout issues with multi-line, centered button titles.
        let title = NSMutableAttributedString(string: message, attributes: attributes)
        title.append(NSAttributedString(string: "  "))
        let attachment = NSTextAttachment()
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        let icon = UIImage(systemName: "arrow.up.right.square", withConfiguration: iconConfig)?
            .withTintColor(.primary, renderingMode: .alwaysOriginal)
        attachment.image = icon
        title.append(NSAttributedString(attachment: attachment))
        messageButton.setAttributedTitle(title, for: .normal)
        messageButton.accessibilityHint = NSLocalizedString(
            "ui_opens_external_link_hint",
            comment: "Accessibility hint for buttons that open say external apps/links"
        )
        
        let backButton = UIButton(type: .system)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.setText(NSLocalizedString("button_back", comment: "Back button title"), .filled)
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        
        view.addSubview(messageButton)
        view.addSubview(backButton)
        
        NSLayoutConstraint.activate([
            messageButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            messageButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            messageButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            backButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            backButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            backButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    @objc private func openWhatsApp() {
        let phoneNumber = "5491134120450"
        let message = "Consulta desde boveda.ai"
        let encodedMessage = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? message
        
        guard let url = URL(string: "https://wa.me/\(phoneNumber)?text=\(encodedMessage)") else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
    
    @objc private func backTapped() {
        // Match PendingVaultActivationViewController behavior:
        // sign out via AuthRepository and let SceneDelegate route to login flow.
        App.shared.authRepository.signOut { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if let sceneDelegate = self.view.window?.windowScene?.delegate as? SceneDelegate {
                    sceneDelegate.onAppUpdateCompletion()
                }
                self.onBack?()
                self.dismiss(animated: true, completion: nil)
            }
        }
    }
}

