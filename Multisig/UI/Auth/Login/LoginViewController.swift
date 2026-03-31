//
//  LoginViewController.swift
//  Multisig
//
//  Created on [Date]
//  Copyright © 2024 Gnosis Ltd. All rights reserved.
//

import UIKit
import Combine
import AuthenticationServices

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
    private var appleSignInButton: ASAuthorizationAppleIDButton?
    private var contactRequiredPresented = false
    @IBOutlet private weak var registerLinkButton: UIButton!
    @IBOutlet private weak var progressIndicator: UIActivityIndicatorView!
    
    // Programmatic UI creation if XIB not available
    private var contentView: UIView?
    
    private var viewModel = LoginViewModel()
    private var cancellables = Set<AnyCancellable>()
    private var keyboardBehavior: KeyboardAvoidingBehavior!
    private var didLogLayoutOnce = false
    private var appleButtonTopToLoginConstraint: NSLayoutConstraint?
    private var appleButtonTopToSubtitleConstraint: NSLayoutConstraint?
    private var progressIndicatorTopToLoginConstraint: NSLayoutConstraint?
    private var progressIndicatorTopToAppleConstraint: NSLayoutConstraint?
    private var isAppleSignInStarting = false
    
    private var shouldShowEmailPasswordLogin: Bool {
        App.configuration.app.showEmailPasswordLogin
    }

    /// Matches list/card surfaces so spacer and safe-area regions are not darker than the form chrome.
    private static let screenFillColor = UIColor.backgroundSecondary
    
    convenience init() {
        self.init(nibName: nil, bundle: nil)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        AuthLogger.info("LoginViewController view created")
        NSLog("[AUTH][LoginVC] viewDidLoad()")
        
        // Create UI programmatically if XIB not available
        if scrollView == nil {
            AuthLogger.info("LoginViewController using programmatic UI (scrollView outlet is nil)")
            NSLog("[AUTH][LoginVC] using programmatic UI (scrollView=nil)")
            setupUIProgrammatically()
        } else {
            AuthLogger.info("LoginViewController using XIB UI (scrollView outlet is non-nil)")
            NSLog("[AUTH][LoginVC] using XIB UI (scrollView!=nil)")
            setupUI()
        }
        
        configureLoginOptions()
        
        observeAuthState()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !didLogLayoutOnce else { return }
        didLogLayoutOnce = true

        let appleFrame = appleSignInButton?.frame ?? .zero
        let registerFrame = registerLinkButton?.frame ?? .zero
        let loginFrame = loginButton?.frame ?? .zero
        AuthLogger.debug("Layout frames - login=\(loginFrame), apple=\(appleFrame), register=\(registerFrame)")
        NSLog("[AUTH][LoginVC] frames login=%@ apple=%@ register=%@",
              NSCoder.string(for: loginFrame),
              NSCoder.string(for: appleFrame),
              NSCoder.string(for: registerFrame))

        if let apple = appleSignInButton {
            AuthLogger.debug("Apple button - enabled=\(apple.isEnabled) hidden=\(apple.isHidden) alpha=\(apple.alpha) userInteraction=\(apple.isUserInteractionEnabled)")
            NSLog("[AUTH][LoginVC] apple enabled=%d hidden=%d alpha=%.2f userInteraction=%d",
                  apple.isEnabled ? 1 : 0,
                  apple.isHidden ? 1 : 0,
                  apple.alpha,
                  apple.isUserInteractionEnabled ? 1 : 0)
            // Also log which view currently wins hit-testing over the center of the Apple button.
            let center = CGPoint(x: appleFrame.midX, y: appleFrame.midY)
            let globalCenter = apple.superview?.convert(center, to: view) ?? center
            let hit = view.hitTest(globalCenter, with: nil)
            AuthLogger.debug("HitTest at Apple center -> \(String(describing: hit))")
            NSLog("[AUTH][LoginVC] hitTest at Apple center -> %@", String(describing: hit))
        } else {
            AuthLogger.warning("Apple button is nil after layout")
            NSLog("[AUTH][LoginVC] apple button is nil after layout")
        }
    }
    
    private func setupUIProgrammatically() {
        view.backgroundColor = Self.screenFillColor
        AuthLogger.debug("setupUIProgrammatically() start")
        NSLog("[AUTH][LoginVC] setupUIProgrammatically() start")
        
        // Create scroll view (full-bleed under status bar; safe area via contentInsetAdjustment)
        let scrollView = UIScrollView()
        scrollView.backgroundColor = Self.screenFillColor
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        self.scrollView = scrollView
        
        // Create content view
        let contentView = UIView()
        contentView.backgroundColor = Self.screenFillColor
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        self.contentView = contentView

        // Spacers keep login content vertically centered when there is extra space.
        let topSpacerView = UIView()
        topSpacerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(topSpacerView)

        let bottomSpacerView = UIView()
        bottomSpacerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bottomSpacerView)
        
        // Create logo
        let logoImageView = UIImageView()
        logoImageView.image = UIImage(named: "ico-safe-bar-logo") ?? UIImage(systemName: "lock.shield")
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

        // Create Apple Sign In button
        let appleButton = ASAuthorizationAppleIDButton(type: .signIn, style: .black)
        appleButton.translatesAutoresizingMaskIntoConstraints = false
        appleButton.addTarget(self, action: #selector(appleSignInTapped), for: .touchUpInside)
        appleButton.addTarget(self, action: #selector(appleSignInTouchDown), for: .touchDown)
        appleButton.isUserInteractionEnabled = true
        appleButton.isExclusiveTouch = true
        appleButton.accessibilityIdentifier = "login_apple_sign_in_button"
        // Gesture recognizer as an extra safety net in case UIControl events aren't firing.
        let tapGR = UITapGestureRecognizer(target: self, action: #selector(appleSignInGestureFired(_:)))
        tapGR.cancelsTouchesInView = false
        appleButton.addGestureRecognizer(tapGR)
        contentView.addSubview(appleButton)
        self.appleSignInButton = appleButton
        AuthLogger.debug("Apple Sign In button added to view hierarchy")
        NSLog("[AUTH][LoginVC] Apple Sign In button added")
        
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
        appleButtonTopToLoginConstraint = appleButton.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 16)
        appleButtonTopToSubtitleConstraint = appleButton.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 32)
        
        progressIndicatorTopToLoginConstraint = progressIndicator.topAnchor.constraint(equalTo: loginButton.bottomAnchor, constant: 12)
        progressIndicatorTopToAppleConstraint = progressIndicator.topAnchor.constraint(equalTo: appleButton.bottomAnchor, constant: 12)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor),
            
            topSpacerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            topSpacerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            topSpacerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            topSpacerView.bottomAnchor.constraint(equalTo: logoImageView.topAnchor, constant: -32),
            topSpacerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 0),

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
            
            progressIndicatorTopToLoginConstraint!,
            progressIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            appleButtonTopToLoginConstraint!,
            appleButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            appleButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            appleButton.heightAnchor.constraint(equalToConstant: 50),
            
            registerLinkButton.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 16),
            registerLinkButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            registerLinkButton.bottomAnchor.constraint(equalTo: bottomSpacerView.topAnchor, constant: -32),

            bottomSpacerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bottomSpacerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bottomSpacerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            bottomSpacerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 0)
        ])

        let balancedSpacerConstraint = topSpacerView.heightAnchor.constraint(equalTo: bottomSpacerView.heightAnchor)
        balancedSpacerConstraint.priority = .defaultHigh
        balancedSpacerConstraint.isActive = true

        navigationController?.setNavigationBarHidden(true, animated: false)
        
        keyboardBehavior = KeyboardAvoidingBehavior(scrollView: scrollView)
        AuthLogger.debug("setupUIProgrammatically() done")
        NSLog("[AUTH][LoginVC] setupUIProgrammatically() done")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Programmatic UI path never calls setupUI(); hide bar so layout isn’t inset under an empty nav bar.
        navigationController?.setNavigationBarHidden(true, animated: animated)
        keyboardBehavior.start()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        keyboardBehavior.stop()
    }
    
    private func setupUI() {
        navigationController?.setNavigationBarHidden(true, animated: false)

        view.backgroundColor = Self.screenFillColor
        scrollView.backgroundColor = Self.screenFillColor
        
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
        logoImageView.image = UIImage(named: "ico-safe-bar-logo") ?? UIImage(systemName: "lock.shield")
        logoImageView.contentMode = .scaleAspectFit
    }

    private func configureLoginOptions() {
        let showEmailPassword = shouldShowEmailPasswordLogin
        
        let emailPasswordViews: [UIView] = [
            emailTextField,
            passwordTextField,
            forgotPasswordButton,
            loginButton,
            registerLinkButton
        ]
        
        emailPasswordViews.forEach {
            $0.isHidden = !showEmailPassword
            $0.isUserInteractionEnabled = showEmailPassword
        }
        
        if let appleTopLogin = appleButtonTopToLoginConstraint,
           let appleTopSubtitle = appleButtonTopToSubtitleConstraint {
            appleTopLogin.isActive = showEmailPassword
            appleTopSubtitle.isActive = !showEmailPassword
        }
        
        if let progressTopLogin = progressIndicatorTopToLoginConstraint,
           let progressTopApple = progressIndicatorTopToAppleConstraint {
            progressTopLogin.isActive = showEmailPassword
            progressTopApple.isActive = !showEmailPassword
        }
        
        view.setNeedsLayout()
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
        let isLoadingState: Bool
        if case .loading = state {
            isLoadingState = true
        } else {
            isLoadingState = false
        }
        if !isLoadingState && isAppleSignInStarting {
            isAppleSignInStarting = false
            AuthLogger.debug("Apple sign-in start guard reset for terminal auth state")
            NSLog("[AUTH][LoginVC] apple guard reset state=%@", String(describing: state))
        }
        
        switch state {
        case .idle:
            setLoading(false)
            
        case .loading:
            setLoading(true)
            
        case .success:
            setLoading(false)
            AuthLogger.info("Login successful, re-checking app flow")
            // Re-check the app flow to ensure proper routing (terms, security, etc.)
            if let sceneDelegate = view.window?.windowScene?.delegate as? SceneDelegate {
                sceneDelegate.forceAssetsOnNextMainContent = true
                sceneDelegate.onAppUpdateCompletion()
            }
            
        case .contactRequired(let message):
            setLoading(false)
            AuthLogger.warning("Login requires contact: \(message)")
            presentContactRequired(message: message)
            
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

    private func presentContactRequired(message: String) {
        guard !contactRequiredPresented else { return }
        contactRequiredPresented = true
        let contactVC = ContactRequiredViewController(message: message) { [weak self] in
            self?.contactRequiredPresented = false
        }
        contactVC.modalPresentationStyle = .fullScreen
        present(contactVC, animated: true, completion: nil)
    }
    
    private func setLoading(_ loading: Bool) {
        progressIndicator.isHidden = !loading
        if loading {
            progressIndicator.startAnimating()
        } else {
            progressIndicator.stopAnimating()
        }
        
        loginButton.isEnabled = !loading
        appleSignInButton?.isEnabled = !loading
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
        NSLog("[AUTH][LoginVC] loginButtonTapped()")
        let email = emailTextField.text ?? ""
        let password = passwordTextField.text ?? ""
        AuthLogger.debug("Login attempt for email: \(email)")
        viewModel.signIn(email: email, password: password)
    }

    @objc private func appleSignInTapped() {
        if isAppleSignInStarting {
            AuthLogger.warning("Apple Sign In tap ignored while request is already starting")
            NSLog("[AUTH][LoginVC] appleSignInTapped ignored (already starting)")
            return
        }
        AuthLogger.info("Apple Sign In button clicked")
        NSLog("[AUTH][LoginVC] appleSignInTapped()")

        let anchor: ASPresentationAnchor
        if let w = view.window {
            anchor = w
            AuthLogger.debug("Apple sign-in anchor from view.window")
            NSLog("[AUTH][LoginVC] Apple anchor=view.window")
        } else if let windowScene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene,
                  let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) {
            anchor = keyWindow
            AuthLogger.warning("Apple sign-in anchor fell back to keyWindow (view.window was nil)")
            NSLog("[AUTH][LoginVC] Apple anchor=keyWindow fallback (view.window=nil)")
        } else {
            AuthLogger.error("Apple Sign In attempted but no presentation anchor could be resolved")
            NSLog("[AUTH][LoginVC] Apple anchor ERROR - none available")
            return
        }

        isAppleSignInStarting = true
        AuthLogger.debug("Apple sign-in start guard armed")
        NSLog("[AUTH][LoginVC] apple guard armed")
        viewModel.signInWithApple(presentationAnchor: anchor)
    }

    @objc private func appleSignInTouchDown() {
        AuthLogger.info("Apple Sign In touchDown")
        NSLog("[AUTH][LoginVC] appleSignInTouchDown()")
    }

    @objc private func appleSignInGestureFired(_ gr: UITapGestureRecognizer) {
        AuthLogger.info("Apple Sign In gesture fired (state=\(gr.state.rawValue))")
        NSLog("[AUTH][LoginVC] appleSignInGestureFired state=%ld", gr.state.rawValue)
        // Do not call appleSignInTapped() here to avoid double-triggering; this is purely diagnostic.
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
        guard let url = URL(string: "https://boveda.ai/register") else {
            AuthLogger.warning("Register link URL is invalid")
            return
        }
        openInSafari(url)
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

