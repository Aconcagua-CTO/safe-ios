//
//  PendingVaultActivationViewController.swift
//  Multisig
//
//  Created by Cursor on 2026-01-07.
//

import UIKit

final class PendingVaultActivationViewController: UIViewController {
    var onVaultsRefreshed: (() -> Void)?

    private let vaultImageView = UIImageView()
    private let messageLabel = UILabel()
    private let refreshButton = UIButton(type: .system)
    private let helpButton = UIButton(type: .system)
    private let signOutButton = UIButton(type: .system)

    private var isRefreshingVaults = false

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .backgroundPrimary

        vaultImageView.translatesAutoresizingMaskIntoConstraints = false
        vaultImageView.contentMode = .scaleAspectFit
        vaultImageView.image = UIImage(named: "tab-icon-balances")?.withRenderingMode(.alwaysTemplate)
            ?? UIImage(named: "safe-selector-not-selected-icon")
            ?? UIImage(named: "ico-no-assets")
        vaultImageView.tintColor = .icon

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.setStyle(.body)
        messageLabel.text = NSLocalizedString("pending_vault_activation_loading_message", comment: "")

        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.setText(NSLocalizedString("pending_vault_activation_refresh_button", comment: ""), .filled)
        refreshButton.addTarget(self, action: #selector(refreshTapped), for: .touchUpInside)

        helpButton.translatesAutoresizingMaskIntoConstraints = false
        helpButton.titleLabel?.numberOfLines = 0
        helpButton.titleLabel?.textAlignment = .center
        helpButton.contentHorizontalAlignment = .center
        helpButton.addTarget(self, action: #selector(openWhatsApp), for: .touchUpInside)
        helpButton.setAttributedTitle(makeHelpAttributedTitle(), for: .normal)
        helpButton.accessibilityHint = NSLocalizedString(
            "ui_opens_external_link_hint",
            comment: "Accessibility hint for buttons that open say external apps/links"
        )

        signOutButton.translatesAutoresizingMaskIntoConstraints = false
        signOutButton.setText(NSLocalizedString("ui_settings_sign_out_title", comment: "Sign out button title"), .filledError)
        signOutButton.addTarget(self, action: #selector(signOutTapped), for: .touchUpInside)
        signOutButton.isHidden = !App.shared.authRepository.isAuthenticated()

        view.addSubview(vaultImageView)
        view.addSubview(messageLabel)
        view.addSubview(refreshButton)
        view.addSubview(helpButton)
        view.addSubview(signOutButton)

        NSLayoutConstraint.activate([
            vaultImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 80),
            vaultImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            vaultImageView.heightAnchor.constraint(equalToConstant: 72),
            vaultImageView.widthAnchor.constraint(equalToConstant: 72),

            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            messageLabel.topAnchor.constraint(equalTo: vaultImageView.bottomAnchor, constant: 16),

            refreshButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 24),
            refreshButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            refreshButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            refreshButton.heightAnchor.constraint(equalToConstant: 50),

            helpButton.topAnchor.constraint(equalTo: refreshButton.bottomAnchor, constant: 16),
            helpButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            helpButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            signOutButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            signOutButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            signOutButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            signOutButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    @objc private func refreshTapped() {
        refreshVaults()
    }

    private func refreshVaults() {
        guard App.shared.authRepository.isAuthenticated() else {
            SnackbarViewController.show(
                NSLocalizedString("ui_safe_refresh_login_required", comment: "Login required to refresh vaults"),
                duration: 3.0
            )
            return
        }

        guard !isRefreshingVaults else {
            SnackbarViewController.show(
                NSLocalizedString("ui_safe_refresh_in_progress", comment: "Vault refresh in progress"),
                duration: 2.0
            )
            return
        }

        isRefreshingVaults = true
        refreshButton.isEnabled = false

        // Keep behavior consistent with the manual refresh entrypoint in SwitchSafesViewController:
        // refresh chains info, then force vault sync, then refresh whitelist + tx names.
        ChainManager.updateChainsInfo { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }

                App.shared.vaultsRepository.syncVaultsFromBackend(force: true) { [weak self] result in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.isRefreshingVaults = false
                        self.refreshButton.isEnabled = true

                        switch result {
                        case .success:
                            SnackbarViewController.show(
                                NSLocalizedString("ui_safe_refresh_success", comment: "Vault refresh success"),
                                duration: 3.0
                            )
                            App.shared.tokenWhitelistRepository.syncWhitelist(force: true, network: nil) { _ in }
                            App.shared.transactionNamesRepository.syncTransactionNames(force: true) { _ in }
                            self.onVaultsRefreshed?()
                        case .failure(let error):
                            SnackbarViewController.show(
                                String(format: NSLocalizedString("ui_safe_refresh_failed_format", comment: "Vault refresh failed format"),
                                       error.localizedDescription),
                                duration: 4.0
                            )
                        }
                    }
                }
            }
        }
    }

    private func makeHelpAttributedTitle() -> NSAttributedString {
        let text = "Cualquier consulta estamos para ayudarte"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 17, weight: .regular),
            .foregroundColor: UIColor.primary,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        let title = NSMutableAttributedString(string: text, attributes: attributes)
        title.append(NSAttributedString(string: "  "))

        let attachment = NSTextAttachment()
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        let icon = UIImage(systemName: "arrow.up.right.square", withConfiguration: iconConfig)?
            .withTintColor(.primary, renderingMode: .alwaysOriginal)
        attachment.image = icon
        title.append(NSAttributedString(attachment: attachment))
        return title
    }

    @objc private func openWhatsApp() {
        PublicConfigService.shared.getWhatsAppSupportConfig { phoneNumber, message in
            let encodedMessage = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? message
            guard let url = URL(string: "https://wa.me/\(phoneNumber)?text=\(encodedMessage)") else { return }
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    @objc private func signOutTapped() {
        let alert = UIAlertController(
            title: NSLocalizedString("ui_settings_sign_out_title", comment: "Sign out alert title"),
            message: NSLocalizedString("ui_sign_out_confirm_message", comment: "Sign out confirmation message"),
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: NSLocalizedString("cancel", comment: "Cancel action title"), style: .cancel))
        alert.addAction(
            UIAlertAction(title: NSLocalizedString("ui_settings_sign_out_title", comment: "Sign out action title"), style: .destructive) { [weak self] _ in
                self?.performSignOut()
            }
        )

        present(alert, animated: true)
    }

    private func performSignOut() {
        App.shared.authRepository.signOut { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success:
                    if let sceneDelegate = self.view.window?.windowScene?.delegate as? SceneDelegate {
                        sceneDelegate.onAppUpdateCompletion()
                    }
                case .failure(let error):
                    SnackbarViewController.show(
                        "Failed to sign out: \(error.localizedDescription)",
                        duration: 4.0
                    )
                }
            }
        }
    }
}


