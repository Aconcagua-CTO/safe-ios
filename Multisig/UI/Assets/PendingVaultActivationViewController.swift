//
//  PendingVaultActivationViewController.swift
//  Multisig
//
//  Created by Cursor on 2026-01-07.
//

import UIKit

final class PendingVaultActivationViewController: UIViewController {
    var onVaultsRefreshed: (() -> Void)?

    private enum VaultRefreshSource {
        case timer
        case resume
        case pullToRefresh
    }

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let refreshControl = UIRefreshControl()
    private let vaultImageView = UIImageView()
    private let messageLabel = UILabel()
    #if DEBUG
    private let signOutButton = UIButton(type: .system)
    private let signOutDeleteKeysButton = UIButton(type: .system)
    #endif

    private var isRefreshingVaults = false
    private var pollTimer: Timer?
    private var didBecomeActiveObserver: NSObjectProtocol?
    private var lastVaultRefreshStart: Date?

    private static let pollInterval: TimeInterval = 5
    private static let resumeDebounceInterval: TimeInterval = 2

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .backgroundPrimary

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.refreshControl = refreshControl
        refreshControl.addTarget(self, action: #selector(pullToRefreshTriggered), for: .valueChanged)

        contentView.translatesAutoresizingMaskIntoConstraints = false

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

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(vaultImageView)
        contentView.addSubview(messageLabel)

        #if DEBUG
        signOutButton.translatesAutoresizingMaskIntoConstraints = false
        signOutButton.setText(NSLocalizedString("ui_settings_sign_out_title", comment: "Sign out button title"), .filledError)
        signOutButton.addTarget(self, action: #selector(signOutTapped), for: .touchUpInside)
        signOutButton.isHidden = !App.shared.authRepository.isAuthenticated()

        signOutDeleteKeysButton.translatesAutoresizingMaskIntoConstraints = false
        signOutDeleteKeysButton.setText(
            NSLocalizedString("ui_settings_sign_out_delete_keys_title", comment: "Sign out and delete keys button title"),
            .filledError
        )
        signOutDeleteKeysButton.addTarget(self, action: #selector(signOutAndDeleteKeysTapped), for: .touchUpInside)
        signOutDeleteKeysButton.isHidden = !App.shared.authRepository.isAuthenticated()

        contentView.addSubview(signOutButton)
        contentView.addSubview(signOutDeleteKeysButton)
        #endif

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor),

            vaultImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 80),
            vaultImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            vaultImageView.heightAnchor.constraint(equalToConstant: 72),
            vaultImageView.widthAnchor.constraint(equalToConstant: 72),

            messageLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            messageLabel.topAnchor.constraint(equalTo: vaultImageView.bottomAnchor, constant: 16)
        ])

        #if DEBUG
        NSLayoutConstraint.activate([
            signOutButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 24),
            signOutButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            signOutButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            signOutButton.bottomAnchor.constraint(equalTo: signOutDeleteKeysButton.topAnchor, constant: -12),
            signOutButton.heightAnchor.constraint(equalToConstant: 50),
            signOutDeleteKeysButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            signOutDeleteKeysButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            signOutDeleteKeysButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24),
            signOutDeleteKeysButton.heightAnchor.constraint(equalToConstant: 50)
        ])
        #else
        NSLayoutConstraint.activate([
            messageLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24)
        ])
        #endif
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startPollingTimer()
        registerDidBecomeActiveObserver()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopPollingTimer()
        unregisterDidBecomeActiveObserver()
    }

    deinit {
        stopPollingTimer()
        unregisterDidBecomeActiveObserver()
    }

    @objc private func pullToRefreshTriggered() {
        performVaultRefresh(source: .pullToRefresh)
    }

    private func startPollingTimer() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.performVaultRefresh(source: .timer)
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPollingTimer() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func registerDidBecomeActiveObserver() {
        guard didBecomeActiveObserver == nil else { return }
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppDidBecomeActive()
        }
    }

    private func unregisterDidBecomeActiveObserver() {
        if let observer = didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(observer)
            didBecomeActiveObserver = nil
        }
    }

    private func handleAppDidBecomeActive() {
        guard isViewLoaded, view.window != nil else { return }
        guard App.shared.authRepository.isAuthenticated() else { return }

        if let last = lastVaultRefreshStart, Date().timeIntervalSince(last) < Self.resumeDebounceInterval {
            return
        }

        performVaultRefresh(source: .resume)
    }

    /// Same pipeline as `SwitchSafesViewController` manual refresh: chains → vault sync → whitelist + tx names.
    private func performVaultRefresh(source: VaultRefreshSource) {
        guard App.shared.authRepository.isAuthenticated() else {
            if source == .pullToRefresh {
                refreshControl.endRefreshing()
                SnackbarViewController.show(
                    NSLocalizedString("ui_safe_refresh_login_required", comment: "Login required to refresh vaults"),
                    duration: 3.0
                )
            }
            return
        }

        guard !isRefreshingVaults else {
            if source == .pullToRefresh {
                refreshControl.endRefreshing()
            }
            return
        }

        lastVaultRefreshStart = Date()
        isRefreshingVaults = true

        ChainManager.updateChainsInfo { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }

                App.shared.vaultsRepository.syncVaultsFromBackend(force: true) { [weak self] result in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.isRefreshingVaults = false
                        if source == .pullToRefresh {
                            self.refreshControl.endRefreshing()
                        }

                        switch result {
                        case .success:
                            App.shared.tokenWhitelistRepository.syncWhitelist(force: true, network: nil) { _ in }
                            App.shared.transactionNamesRepository.syncTransactionNames(force: true) { _ in }
                            self.onVaultsRefreshed?()
                        case .failure(let error):
                            SnackbarViewController.show(
                                String(
                                    format: NSLocalizedString("ui_safe_refresh_failed_format", comment: "Vault refresh failed format"),
                                    error.localizedDescription
                                ),
                                duration: 4.0
                            )
                        }
                    }
                }
            }
        }
    }

    #if DEBUG
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
    #endif
}
