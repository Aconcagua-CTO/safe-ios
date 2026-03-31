//
//  PostLoginGateErrorViewController.swift
//  Multisig
//
//  Created by GPT-5.2 Codex.
//

import UIKit

final class PostLoginGateErrorViewController: UIViewController {
    private let message: String
    private let retryTitle: String
    private let onRetry: () -> Void

    private var messageLabel: UILabel!
    private var retryButton: UIButton!
    private var signOutButton: UIButton?
    #if DEBUG
    private var signOutDeleteKeysButton: UIButton?
    #endif

    init(message: String, retryTitle: String, onRetry: @escaping () -> Void) {
        self.message = message
        self.retryTitle = retryTitle
        self.onRetry = onRetry
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        view.backgroundColor = .backgroundPrimary

        messageLabel = UILabel()
        messageLabel.text = message
        messageLabel.textAlignment = .center
        messageLabel.setStyle(.body)
        messageLabel.textColor = .labelSecondary
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        retryButton = UIButton(type: .system)
        retryButton.setText(retryTitle, .filled)
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        view.addSubview(messageLabel)
        view.addSubview(retryButton)

        let showsSignOut = true

        var constraints: [NSLayoutConstraint] = [
            messageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: showsSignOut ? -60 : -24),
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            retryButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            retryButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            retryButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            retryButton.heightAnchor.constraint(equalToConstant: 50)
        ]

        if showsSignOut {
            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setText(NSLocalizedString("ui_settings_sign_out_title", comment: "Sign out button title"), .filledError)
            button.addTarget(self, action: #selector(signOutTapped), for: .touchUpInside)
            view.addSubview(button)
            signOutButton = button

            #if DEBUG
            let deleteKeysButton = UIButton(type: .system)
            deleteKeysButton.translatesAutoresizingMaskIntoConstraints = false
            deleteKeysButton.setText(
                NSLocalizedString("ui_settings_sign_out_delete_keys_title", comment: "Sign out and delete keys button title"),
                .filledError
            )
            deleteKeysButton.addTarget(self, action: #selector(signOutAndDeleteKeysTapped), for: .touchUpInside)
            view.addSubview(deleteKeysButton)
            signOutDeleteKeysButton = deleteKeysButton
            #endif

            #if DEBUG
            let signOutBottomConstraint = button.bottomAnchor.constraint(
                equalTo: deleteKeysButton.topAnchor,
                    constant: -12
            )
            #else
            let signOutBottomConstraint = button.bottomAnchor.constraint(
                equalTo: retryButton.topAnchor,
                constant: -12
            )
            #endif

            constraints.append(contentsOf: [
                button.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
                button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
                signOutBottomConstraint,
                button.heightAnchor.constraint(equalToConstant: 50)
            ])

            #if DEBUG
            constraints.append(contentsOf: [
                deleteKeysButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
                deleteKeysButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
                deleteKeysButton.bottomAnchor.constraint(equalTo: retryButton.topAnchor, constant: -12),
                deleteKeysButton.heightAnchor.constraint(equalToConstant: 50)
            ])
            #endif
        }

        NSLayoutConstraint.activate(constraints)
    }

    @objc private func retryTapped() {
        onRetry()
    }

    @objc private func signOutTapped() {
        // In some cases (e.g. invalid/expired token) Firebase signs the user out automatically
        // *before* we present this error screen. Still provide a clear way to exit the flow.
        guard App.shared.authRepository.isAuthenticated() else {
            routeToLogin()
            return
        }

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

    #if DEBUG
    @objc private func signOutAndDeleteKeysTapped() {
        guard App.shared.authRepository.isAuthenticated() else {
            routeToLogin()
            return
        }

        let alert = UIAlertController(
            title: NSLocalizedString("ui_settings_sign_out_delete_keys_title", comment: "Sign out and delete keys alert title"),
            message: "Esto va a borrar las llaves locales y cerrar sesión. Continuar?",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: NSLocalizedString("cancel", comment: "Cancel action title"), style: .cancel))
        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("ui_settings_sign_out_delete_keys_title", comment: "Sign out and delete keys action title"),
                style: .destructive
            ) { [weak self] _ in
                self?.performDeleteKeysAndSignOut()
            }
        )

        present(alert, animated: true)
    }

    private func performDeleteKeysAndSignOut() {
        do {
            try OwnerKeyController.deleteAllKeys(showingMessage: false)
        } catch {
            SnackbarViewController.show(
                "No se pudieron borrar las llaves locales: \(error.localizedDescription)",
                duration: 4.0
            )
            return
        }

        performSignOut()
    }
    #endif

    private func routeToLogin() {
        if let sceneDelegate = view.window?.windowScene?.delegate as? SceneDelegate {
            sceneDelegate.onAppUpdateCompletion()
        }
    }

    private func performSignOut() {
        signOutButton?.isEnabled = false
        retryButton.isEnabled = false

        App.shared.authRepository.signOut { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.signOutButton?.isEnabled = true
                self.retryButton.isEnabled = true

                switch result {
                case .success:
                    self.routeToLogin()
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
