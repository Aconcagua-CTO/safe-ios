//
//  VaultSyncErrorViewController.swift
//  Multisig
//
//  Created on [Date]
//  Copyright © 2024 Gnosis Ltd. All rights reserved.
//

import UIKit

class VaultSyncErrorViewController: UIViewController {
    private let message: String
    private let showsSignOut: Bool
    private var messageLabel: UILabel!
    private var signOutButton: UIButton?
    #if DEBUG
    private var signOutDeleteKeysButton: UIButton?
    #endif
    
    init(message: String, showsSignOut: Bool = false) {
        self.message = message
        self.showsSignOut = showsSignOut
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
        
        view.addSubview(messageLabel)

        var constraints: [NSLayoutConstraint] = [
            messageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: showsSignOut ? -40 : 0),
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ]

        if showsSignOut, App.shared.authRepository.isAuthenticated() {
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
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -24
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
                deleteKeysButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
                deleteKeysButton.heightAnchor.constraint(equalToConstant: 50)
            ])
            #endif
        }

        NSLayoutConstraint.activate(constraints)
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

    #if DEBUG
    @objc private func signOutAndDeleteKeysTapped() {
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

