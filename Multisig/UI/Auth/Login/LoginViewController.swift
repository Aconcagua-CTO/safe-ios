//
//  LoginViewController.swift
//  Multisig
//
//  Created on [Date]
//  Copyright © [Year] Gnosis Ltd. All rights reserved.
//

import UIKit
import Combine

/**
 * Login screen ViewController
 * Allows users to sign in with email and password
 */
class LoginViewController: UIViewController {
    
    @IBOutlet private weak var scrollView: UIScrollView!
    @IBOutlet private weak var logoImageView: UIImageView!
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var subtitleLabel: UILabel!
    @IBOutlet private weak var emailTextField: GNOTextField!
    @IBOutlet private weak var passwordTextField: GNOTextField!
    @IBOutlet private weak var forgotPasswordButton: UIButton!
    @IBOutlet private weak var loginButton: UIButton!
    @IBOutlet private weak var registerLinkButton: UIButton!
    @IBOutlet private weak var progressIndicator: UIActivityIndicatorView!
    
    // Programmatic UI creation if XIB not available
    private var contentView: UIView?
    
    private var viewModel = LoginViewModel()
    private var cancellables = Set<AnyCancellable>()
    private var keyboardBehavior: KeyboardAvoidingBehavior!
    
    convenience init() {
        self.init(nibName: nil, bundle: nil)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        AuthLogger.info("LoginViewController view created")
        
        // Create UI programmatically if XIB not available
        if scrollView == nil {
            setupUIProgrammatically()
        } else {
            setupUI()
        }
        
        observeAuthState()
    }
    
    private func setupUIProgrammatically() {
        view.backgroundColor = .backgroundPrimary
        
        // Create scroll view
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        self.scrollView = scrollView
        
        // Create content view
        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        self.contentView = contentView
        
        // Create logo
        let logoImageView = UIImageView()
        logoImageView.image = UIImage(named: "ico-safe") ?? UIImage(systemName: "lock.shield")
        logoImageView.contentMode = .scaleAspectFit
        logoImageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(logoImageView)
        self.logoImageView = logoImageView
        
        // Create title label
        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("auth_welcome_title", comment: "")
        titleLabel.setStyle(.headline)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        self.titleLabel = titleLabel
        
        // Create subtitle label
        let subtitleLabel = UILabel()
        subtitleLabel.text = NSLocalizedString("auth_login_subtitle", comment: "")
        subtitleLabel.setStyle(.body)
        subtitleLabel.textAlignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(subtitleLabel)
        self.subtitleLabel = subtitleLabel
        
        // Create email text field
        let emailTextField = GNOTextField()
        emailTextField.translatesAutoresizingMaskIntoConstraints = false
        emailTextField.setPlaceholder(NSLocalizedString("auth_email_placeholder", comment: ""))
        emailTextField.textField.keyboardType = .emailAddress
        emailTextField.textField.autocapitalizationType = .none
        emailTextField.textField.autocorrectionType = .no
        emailTextField.textField.delegate = self
        emailTextField.textField.addTarget(self, action: #selector(emailTextFieldDidChange), for: .editingChanged)
        contentView.addSubview(emailTextField)
        self.emailTextField = emailTextField
        
        // Create password text field
        let passwordTextField = GNOTextField()
        passwordTextField.translatesAutoresizingMaskIntoConstraints = false
        passwordTextField.setPlaceholder(NSLocalizedString("auth_password_placeholder", comment: ""))
        passwordTextField.textField.isSecureTextEntry = true
        passwordTextField.textField.delegate = self
        passwordTextField.textField.addTarget(self, action: #selector(passwordTextFieldDidChange), for: .editingChanged)
        contentView.addSubview(passwordTextField)
        self.passwordTextField = passwordTextField
        
        // Create forgot password button
        let forgotPasswordButton = UIButton(type: .system)
        forgotPasswordButton.setTitle(NSLocalizedString("auth_forgot_password", comment: ""), for: .normal)
        forgotPasswordButton.setTitleColor(.primary, for: .normal)
        forgotPasswordButton.addTarget(self, action: #selector(forgotPasswordTapped), for: .touchUpInside)
        forgotPasswordButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(forgotPasswordButton)
        self.forgotPasswordButton = forgotPasswordButton
        
        // Create login button
        let loginButton = UIButton(type: .system)
        loginButton.setText(NSLocalizedString("auth_login_button", comment: ""), .filled)
        loginButton.addTarget(self, action: #selector(loginButtonTapped), for: .touchUpInside)
        loginButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(loginButton)
        self.loginButton = loginButton
        
        // Create register link button
        let registerLinkButton = UIButton(type: .system)
        registerLinkButton.setTitle(NSLocalizedString("auth_register_link", comment: ""), for: .normal)
        registerLinkButton.setTitleColor(.primary, for: .normal)
        registerLinkButton.addTarget(self, action: #selector(registerLinkTapped), for: .touchUpInside)
        registerLinkButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(registerLinkButton)
        self.registerLinkButton = registerLinkButton
        
        // Create progress indicator
        let progressIndicator = UIActivityIndicatorView(style: .medium)
        progressIndicator.hidesWhenStopped = true
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(progressIndicator)
        self.progressIndicator = progressIndicator
        
        // Setup constraints
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            logoImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32),
            logoImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            logoImageView.widthAnchor.constraint(equalToConstant: 120),
            logoImageView.heightAnchor.constraint(equalToConstant: 120),
            
            titleLabel.topAnchor.constraint(equalTo: logoImageView.bottomAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            
            emailTextField.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 32),
            emailTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            emailTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            
            passwordTextField.topAnchor.constraint(equalTo: emailTextField.bottomAnchor, constant: 16),
            passwordTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            passwordTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            
            forgotPasswordButton.topAnchor.constraint(equalTo: passwordTextField.bottomAnchor, constant: 8),
            forgotPasswordButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            
            loginButton.topAnchor.constraint(equalTo: forgotPasswordButton.bottomAnchor, constant: 24),
            loginButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            loginButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            loginButton.heightAnchor.constraint(equalToConstant: 50),
            
            progressIndicator.centerXAnchor.constraint(equalTo: loginButton.centerXAnchor),
            progressIndicator.centerYAnchor.constraint(equalTo: loginButton.centerYAnchor),
            
            registerLinkButton.topAnchor.constraint(equalTo: loginButton.bottomAnchor, constant: 16),
            registerLinkButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            registerLinkButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32)
        ])
        
        keyboardBehavior = KeyboardAvoidingBehavior(scrollView: scrollView)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        keyboardBehavior.start()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        keyboardBehavior.stop()
    }
    
    private func setupUI() {
        // Setup navigation bar
        navigationController?.navigationBar.isHidden = true
        
        // Setup keyboard behavior
        keyboardBehavior = KeyboardAvoidingBehavior(scrollView: scrollView)
        
        // Setup labels
        titleLabel.text = NSLocalizedString("auth_welcome_title", comment: "")
        titleLabel.setStyle(.headline)
        
        subtitleLabel.text = NSLocalizedString("auth_login_subtitle", comment: "")
        subtitleLabel.setStyle(.body)
        
        // Setup text fields
        emailTextField.setPlaceholder(NSLocalizedString("auth_email_placeholder", comment: ""))
        emailTextField.textField.keyboardType = .emailAddress
        emailTextField.textField.autocapitalizationType = .none
        emailTextField.textField.autocorrectionType = .no
        emailTextField.textField.delegate = self
        emailTextField.textField.addTarget(self, action: #selector(emailTextFieldDidChange), for: .editingChanged)
        
        passwordTextField.setPlaceholder(NSLocalizedString("auth_password_placeholder", comment: ""))
        passwordTextField.textField.isSecureTextEntry = true
        passwordTextField.textField.delegate = self
        passwordTextField.textField.addTarget(self, action: #selector(passwordTextFieldDidChange), for: .editingChanged)
        
        // Setup buttons
        forgotPasswordButton.setTitle(NSLocalizedString("auth_forgot_password", comment: ""), for: .normal)
        forgotPasswordButton.setTitleColor(.primary, for: .normal)
        forgotPasswordButton.addTarget(self, action: #selector(forgotPasswordTapped), for: .touchUpInside)
        
        loginButton.setText(NSLocalizedString("auth_login_button", comment: ""), .filled)
        loginButton.addTarget(self, action: #selector(loginButtonTapped), for: .touchUpInside)
        
        registerLinkButton.setTitle(NSLocalizedString("auth_register_link", comment: ""), for: .normal)
        registerLinkButton.setTitleColor(.primary, for: .normal)
        registerLinkButton.addTarget(self, action: #selector(registerLinkTapped), for: .touchUpInside)
        
        // Setup progress indicator
        progressIndicator.hidesWhenStopped = true
        progressIndicator.style = .medium
        
        // Setup logo
        logoImageView.image = UIImage(named: "ico-safe") ?? UIImage(systemName: "lock.shield")
        logoImageView.contentMode = .scaleAspectFit
    }
    
    private func observeAuthState() {
        viewModel.$authState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                self.handleAuthState(state)
            }
            .store(in: &cancellables)
    }
    
    private func handleAuthState(_ state: AuthState) {
        AuthLogger.debug("LoginViewController received auth state: \(state)")
        
        switch state {
        case .idle:
            setLoading(false)
            
        case .loading:
            setLoading(true)
            
        case .success:
            setLoading(false)
            AuthLogger.info("Login successful, navigating to main app")
            // Navigate to main app
            if let sceneDelegate = view.window?.windowScene?.delegate as? SceneDelegate {
                sceneDelegate.showMainContentWindow()
            }
            
        case .error(let message, let exception):
            setLoading(false)
            AuthLogger.error("Login error: \(message)", error: exception)
            
            // Show error message
            SnackbarViewController.show(message, duration: 4.0)
            
            // Show inline errors for validation failures
            if message.contains(NSLocalizedString("auth_email_required", comment: "")) ||
               message.contains(NSLocalizedString("auth_invalid_email", comment: "")) {
                emailTextField.setErrorText(message)
            } else if message.contains(NSLocalizedString("auth_password_required", comment: "")) {
                passwordTextField.setErrorText(message)
            }
            
            viewModel.resetState()
        }
    }
    
    private func setLoading(_ loading: Bool) {
        progressIndicator.isHidden = !loading
        if loading {
            progressIndicator.startAnimating()
        } else {
            progressIndicator.stopAnimating()
        }
        
        loginButton.isEnabled = !loading
        emailTextField.textField.isEnabled = !loading
        passwordTextField.textField.isEnabled = !loading
    }
    
    @objc private func emailTextFieldDidChange() {
        emailTextField.setErrorText(nil)
    }
    
    @objc private func passwordTextFieldDidChange() {
        passwordTextField.setErrorText(nil)
    }
    
    @objc private func loginButtonTapped() {
        AuthLogger.info("Login button clicked")
        let email = emailTextField.text ?? ""
        let password = passwordTextField.text ?? ""
        AuthLogger.debug("Login attempt for email: \(email)")
        viewModel.signIn(email: email, password: password)
    }
    
    @objc private func forgotPasswordTapped() {
        AuthLogger.info("Forgot password clicked")
        let email = emailTextField.text ?? ""
        
        if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            AuthLogger.warning("Forgot password clicked but email is empty")
            emailTextField.setErrorText(NSLocalizedString("auth_email_required", comment: ""))
            return
        }
        
        viewModel.resetPassword(email: email)
        
        // Show success message
        SnackbarViewController.show(
            NSLocalizedString("auth_password_reset_sent", comment: ""),
            duration: 4.0,
            icon: .success
        )
    }
    
    @objc private func registerLinkTapped() {
        AuthLogger.info("Register link clicked")
        // TODO: Navigate to registration screen when implemented
        // For now, just show a message
        SnackbarViewController.show("Registration screen coming soon", duration: 3.0)
    }
}

// MARK: - UITextFieldDelegate

extension LoginViewController: UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        keyboardBehavior.activeTextField = textField
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField == emailTextField.textField {
            passwordTextField.textField.becomeFirstResponder()
        } else if textField == passwordTextField.textField {
            textField.resignFirstResponder()
            loginButtonTapped()
        }
        return true
    }
}

