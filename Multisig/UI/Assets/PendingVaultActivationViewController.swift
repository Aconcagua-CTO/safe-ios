//
//  PendingVaultActivationViewController.swift
//  Multisig
//
//  Created by Cursor on 2026-01-07.
//

import UIKit

final class PendingVaultActivationViewController: UIViewController {
    var onVaultsRefreshed: (() -> Void)?

    private let messageLabel = UILabel()
    private let refreshButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    private var isRefreshing = false {
        didSet { updateRefreshingState() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .backgroundPrimary

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.setStyle(.body)
        messageLabel.text = NSLocalizedString("pending_vault_activation_message", comment: "")

        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.setText(NSLocalizedString("pending_vault_activation_refresh_button", comment: ""), .filled)
        refreshButton.addTarget(self, action: #selector(refreshTapped), for: .touchUpInside)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true

        view.addSubview(messageLabel)
        view.addSubview(refreshButton)
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            messageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),

            refreshButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 24),
            refreshButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            refreshButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            refreshButton.heightAnchor.constraint(equalToConstant: 50),

            activityIndicator.centerXAnchor.constraint(equalTo: refreshButton.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: refreshButton.centerYAnchor)
        ])
    }

    @objc private func refreshTapped() {
        guard !isRefreshing else { return }
        isRefreshing = true

        App.shared.vaultsRepository.syncVaultsFromBackend(force: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefreshing = false
                self.onVaultsRefreshed?()
            }
        }
    }

    private func updateRefreshingState() {
        refreshButton.isEnabled = !isRefreshing
        if isRefreshing {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
    }
}


