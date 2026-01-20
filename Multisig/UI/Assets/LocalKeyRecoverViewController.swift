//
//  LocalKeyRecoverViewController.swift
//  Multisig
//
//  Created by Cursor on 2026-01-07.
//

import UIKit

final class LocalKeyRecoverViewController: UIViewController {
    private let messageLabel = UILabel()
    private let whatsappButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .backgroundPrimary

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.setStyle(.body)
        messageLabel.text = NSLocalizedString("local_key_recover_message", comment: "")

        whatsappButton.translatesAutoresizingMaskIntoConstraints = false
        let linkText = NSLocalizedString("local_key_recover_whatsapp_link", comment: "")
        let attributed = NSAttributedString(
            string: linkText,
            attributes: [
                .foregroundColor: UIColor.primary,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .font: UIFont.preferredFont(forTextStyle: .subheadline)
            ]
        )
        whatsappButton.setAttributedTitle(attributed, for: .normal)
        whatsappButton.setTitleColor(.primary, for: .normal)
        whatsappButton.titleLabel?.numberOfLines = 0
        whatsappButton.titleLabel?.textAlignment = .center
        whatsappButton.addTarget(self, action: #selector(openWhatsApp), for: .touchUpInside)

        view.addSubview(messageLabel)
        view.addSubview(whatsappButton)

        NSLayoutConstraint.activate([
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            messageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),

            whatsappButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 16),
            whatsappButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            whatsappButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }

    @objc private func openWhatsApp() {
        // Reuse same wa.me number/message used in WhatsAppLinkView (SafeInfoView.swift)
        let phoneNumber = "5491134120450"
        let message = "Consulta desde boveda.ai"
        let encodedMessage = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? message

        guard let url = URL(string: "https://wa.me/\(phoneNumber)?text=\(encodedMessage)") else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}


