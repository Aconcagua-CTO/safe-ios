//
//  SceneDelegate.swift
//  Multisig
//
//  Created by Dmitry Bespalov. on 14.04.20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//
import UIKit
import SwiftUI
import CustomAuth

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var snackbarViewController = SnackbarViewController(nibName: nil, bundle: nil)

    var updateAppWindow: UIWindow?
    var tabBarWindow: UIWindow?
    var privacyShieldWindow: UIWindow?
    var postLoginGateWindow: UIWindow?
    var forceAssetsOnNextMainContent: Bool = false

    // the window to present
    var presentedWindow: UIWindow?
    private var postLoginGateCoordinator: PostLoginGateCoordinator?
    
    // Gate to prevent unapproved users (lead not approved) from entering the app on relaunch.
    private var isCheckingProvisioningGate = false
    private var provisioningGateApprovedUid: String?
    private lazy var userProvisioningService =
        UserProvisioningService(authRepository: App.shared.authRepository, logger: LogService.shared)

    private var shouldShowPasscode: Bool {
        App.shared.auth.isPasscodeSetAndAvailable && AppSettings.passcodeOptions.contains(.useForLogin)
    }

    private var startedFromNotification: Bool {
        get { App.shared.appReview.startedFromNotification }
        set { App.shared.appReview.startedFromNotification = newValue }
    }

    weak var scene: UIWindowScene?

    // MARK: - Scene Life Cycle
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
#if DEBUG
        guard UIApplication.shared.delegate is AppDelegate else {
            // assume we're in a testing mode, so exit any further configuration
            return
        }
#endif

        App.shared.notificationHandler.appStarted()
        startedFromNotification = connectionOptions.notificationResponse != nil

        if let scene = scene as? UIWindowScene {
            self.scene = scene
            makeWindows(scene: scene)
        }

        App.shared.appReview.startedFromNotification = connectionOptions.notificationResponse != nil

        if let userActivity = connectionOptions.userActivities.first {
            handleUserActivity(userActivity)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(handlePasscodeRequired),
                                               name: .passcodeRequired,
                                               object: nil)
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
#if DEBUG
        guard UIApplication.shared.delegate is AppDelegate else {
            // assume we're in a testing mode, so exit any further configuration
            return
        }
#endif

        App.shared.notificationHandler.appEnteredForeground()

        if scene.activationState == .unattached && updateAppWindow?.rootViewController != nil {
            showWindow(updateAppWindow)
        } else {
            onAppUpdateCompletion()
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
#if DEBUG
        guard UIApplication.shared.delegate is AppDelegate else {
            // assume we're in a testing mode, so exit any further configuration
            return
        }
#endif

        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
        App.shared.clientGatewayHostObserver.startObserving()

        PendingTransactionMonitor.scheduleMonitoring()
        RelayedTransactionMonitor.scheduleMonitoring()
        SafeCreationMonitor.scheduleMonitoring()
        WebConnectionExpirationMonitor.scheduleMonitoring()

        privacyShieldWindow?.isHidden = true

        if let viewController = updateAppWindow?.rootViewController as? UpdateAppViewController, viewController.style == .required {
            showWindow(updateAppWindow)
        }
    }

    func sceneWillResignActive(_ scene: UIScene) {
#if DEBUG
        guard UIApplication.shared.delegate is AppDelegate else {
            // assume we're in a testing mode, so exit any further configuration
            return
        }
#endif

        App.shared.clientGatewayHostObserver.stopObserving()

        PendingTransactionMonitor.stopMonitoring()
        WebConnectionExpirationMonitor.stopMonitoring()

        if presentedWindow === tabBarWindow {
            privacyShieldWindow?.isHidden = false
        }
        IntercomConfig.hide()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
#if DEBUG
        guard UIApplication.shared.delegate is AppDelegate else {
            // assume we're in a testing mode, so exit any further configuration
            return
        }
#endif
        // Save changes in the application's managed object context when the application transitions to the background.
        App.shared.coreDataStack.saveContext()

        App.shared.securityCenter.lockDataStore()
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
#if DEBUG
        guard UIApplication.shared.delegate is AppDelegate else {
            // assume we're in a testing mode, so exit any further configuration
            return
        }
#endif

        handleUserActivity(userActivity)
    }
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        _ = handleURL(wcURL: URLContexts.first?.url.absoluteString)
    }
    
    

    // Handles opening of a universal link.
    //
    // Supported link types:
    // - WalletConnect links from dapps to connect to the safe
    //   - 'connect' link to establish new connection
    //   - 'open' link to move the app to foreground so that it is able to process WalletConnect request or response.
    // - Request To Add Owner 
    //   - <web app url>/settings/setup?safe=<safe_address>&address=<owner_address>
    // - Web3auth
    //   - handled by CustomAuth.handle()
    private func handleUserActivity(_ userActivity: NSUserActivity) {
        // Get URL components from the incoming user activity.
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let incomingURL = userActivity.webpageURL,
              let components = NSURLComponents(url: incomingURL, resolvingAgainstBaseURL: true) else {
            return
        }

        // handle wallet connect
        let didHandleURL = handleURL(wcURL: components.queryItems?.first?.value)
        if didHandleURL {
            return
        }
        

        // handle request to add owner
        if AddOwnerRequestValidator.isValid(url: incomingURL),
           let params = AddOwnerRequestValidator.parameters(from: incomingURL) {
            CompositeNavigationRouter.shared.navigate(to: .requestToAddOwner(params))
            return
        }

        if let navigationRoute = CompositeNavigationRouter.shared.routeFrom(from: incomingURL) {
            CompositeNavigationRouter.shared.navigate(to: navigationRoute)
        }
    }
    
    private func handleURL(wcURL: String?) -> Bool {
        guard let wcURL = wcURL, (try? Safe.getSelected()) != nil else { return false }
        if WalletConnectManager.shared.canConnect(url: wcURL) {
            WalletConnectManager.shared.pairClient(url: wcURL, trackingEvent: .dappConnectedWithUniversalLink)
            return true
        } else if WalletConnectSafesServerController.shared.canConnect(url: wcURL) {
            try? WalletConnectSafesServerController.shared.connect(url: wcURL)
            WalletConnectSafesServerController.shared.dappConnectedTrackingEvent = .dappConnectedWithUniversalLink
            return true
        } else {
            return false
        }
    }

    // MARK: - Window Management

    func present(_ controller: UIViewController) {
        tabBarWindow?.rootViewController?.present(controller, animated: true)
    }

    private func makeWindow(scene: UIWindowScene) -> UIWindow {
        let window = WindowWithViewOnTop(windowScene: scene)
        window.tintColor = .primary

        return window
    }

    private func showWindow(_ window: UIWindow?) {
        guard let window = window else { return }

        if let customWindow = window as? WindowWithViewOnTop {
            snackbarViewController.view.frame = customWindow.bounds
            customWindow.addSubviewAlwaysOnTop(snackbarViewController.view)
        }

        window.makeKeyAndVisible()
        App.shared.theme.setUp()
        presentedWindow = window
    }

    private func makeWindows(scene: UIWindowScene) {
        // snack bar
        SnackbarViewController.instance = snackbarViewController
        snackbarViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        updateAppWindow = makeUpdateAppWindow()
        tabBarWindow = makeTabBarWindow()
        privacyShieldWindow = makePrivacyShieldWindow()
    }

    func makeUpdateAppWindow() -> UIWindow {
        let updateAppWindow = makeWindow(scene: scene!)
        if let controller = App.shared.updateController.makeUpdateAppViewController() {
            updateAppWindow.rootViewController = controller

            controller.completion = { [unowned self] in
                onAppUpdateCompletion()
            }
        }
        return updateAppWindow
    }

    func makeTabBarWindow() -> UIWindow {
        let tabBarWindow = makeWindow(scene: scene!)
        tabBarWindow.rootViewController = ViewControllerFactory.tabBarViewController(completion: { [unowned self] tabBar in
            onTabBarAppearance(of: tabBar)
        })
        return tabBarWindow
    }

    func makeFaceIDUnlockWindow() -> UIWindow {
        let faceIDUnlockWindow = makeWindow(scene: scene!)
        faceIDUnlockWindow.rootViewController = ViewControllerFactory.faceIDUnlockViewController { [unowned self] success, reset in
            #if DEBUG
            LogService.shared.debug("[SceneDelegate] Face ID completion - success: \(success), reset: \(reset)")
            #endif
            
            if success {
                onFaceIDCheckCompletion()
            } else {
                // Face ID failed or cancelled - fall back to passcode if lock method requires it
                let shouldShowPasscodeEntry = App.shared.securityCenter.shouldShowPasscode()
                
                #if DEBUG
                LogService.shared.debug("[SceneDelegate] Face ID failed - shouldShowPasscode: \(shouldShowPasscodeEntry)")
                #endif
                
                if shouldShowPasscodeEntry {
                    #if DEBUG
                    LogService.shared.debug("[SceneDelegate] Falling back to passcode window")
                    #endif
                    forceAssetsOnNextMainContent = false
                    showWindow(makeEnterPasscodeWindow())
                } else {
                    // Biometry-only mode failed - stay on Face ID screen for retry
                    // The user can tap the unlock button to retry
                    #if DEBUG
                    LogService.shared.debug("[SceneDelegate] Staying on Face ID screen (biometry-only mode)")
                    #endif
                }
            }
        }
        return faceIDUnlockWindow
    }


    func makeEnterPasscodeWindow(showsCloseButton: Bool = false,
                                 completion: ((EnterPasscodeViewController.Result) -> Void)? = nil) -> UIWindow {
        let enterPasscodeWindow = makeWindow(scene: scene!)

        let isGlobalUnlock = AppConfiguration.FeatureToggles.securityCenter && !showsCloseButton
        let securityCenterBehavior: EnterPasscodeViewController.SecurityCenterBehavior =
            isGlobalUnlock ? .unlockDataStoreForAppUnlock : .validateOnly

        let vc = ViewControllerFactory.enterPasscodeViewController(
            showsCloseButton: showsCloseButton,
            securityCenterBehavior: securityCenterBehavior
        ) { [unowned self] result in
            switch result {
            case .success(let passcode):
                // If this is the global app-unlock flow under SecurityCenter, the passcode VC already
                // unlocked the data store (to avoid doing the expensive work twice).
                if isGlobalUnlock {
                    showMainContentWindow()
                } else {
                    onEnterPasscodeCompletion(userPassword: passcode)
                }
            case .close:
                showMainContentWindow()
            }

            completion?(result)
        }

        enterPasscodeWindow.rootViewController = vc
        return enterPasscodeWindow
    }

    func makePrivacyShieldWindow() -> UIWindow {
        let privacyShieldWindow = makeWindow(scene: scene!)
        privacyShieldWindow.rootViewController = PrivacyProtectionScreenViewController()
        return privacyShieldWindow
    }

    func makeTermsWindow() -> UIWindow {
        let termsWindow = makeWindow(scene: scene!)
        termsWindow.rootViewController = ViewControllerFactory.termsViewController { [unowned self] in
            onTermsCompletion()
        }
        return termsWindow
    }

    func showOnboardingWindow() {
        if let presentedWindow = presentedWindow,
           let root = presentedWindow.rootViewController,
           root is OnboardingViewController {
            return
        }

        showWindow(makeOnboardingWindow())
    }

    func makeOnboardingWindow() -> UIWindow {
        AppSettings.onboardingCompleted = false

        let onboardingWindow = makeWindow(scene: scene!)
        onboardingWindow.rootViewController = OnboardingViewController(completion: { [unowned self] in
            AppSettings.onboardingCompleted = true
            onOnboardingCompletion()
        })

        return onboardingWindow
    }

    func onAppUpdateCompletion() {
        // Check terms first - if not accepted, show launch screen and terms
        if !AppSettings.termsAccepted {
            AuthLogger.info("Terms not accepted, showing launch screen and terms")
            showWindow(makeTermsWindow())
            return
        }
        
        // Terms accepted - check authentication state
        if !App.shared.authRepository.isAuthenticated() {
            AuthLogger.info("User not authenticated, showing login screen")
            postLoginGateCoordinator = nil
            dismissPostLoginGateWindow()
            showWindow(makeLoginWindow())
            return
        }
        
        // Terms accepted and user authenticated - proceed with security checks
        AuthLogger.info("User authenticated, proceeding with normal app flow")
        
        #if DEBUG
        LogService.shared.debug("[SceneDelegate] Checking security unlock flow")
        LogService.shared.debug("[SceneDelegate] SecurityCenter enabled: \(AppConfiguration.FeatureToggles.securityCenter)")
        LogService.shared.debug("[SceneDelegate] shouldShowPasscode (legacy): \(shouldShowPasscode)")
        #endif
        
        if shouldShowPasscode && !AppConfiguration.FeatureToggles.securityCenter {
            #if DEBUG
            LogService.shared.debug("[SceneDelegate] Showing legacy passcode window")
            #endif
            showWindow(makeEnterPasscodeWindow())
        } else if App.shared.securityCenter.shouldShowFaceID() {
            #if DEBUG
            LogService.shared.debug("[SceneDelegate] Showing Face ID window")
            #endif
            showWindow(makeFaceIDUnlockWindow())
        } else if App.shared.securityCenter.shouldShowPasscode() {
            #if DEBUG
            LogService.shared.debug("[SceneDelegate] Showing passcode window")
            #endif
            showWindow(makeEnterPasscodeWindow())
        } else {
            // Go directly to main content (assets screen) after post-login gating
            #if DEBUG
            LogService.shared.debug("[SceneDelegate] No unlock needed, showing post-login gate")
            #endif
            showPostLoginGateIfNeeded()
        }
    }
    
    func makeLoginWindow() -> UIWindow {
        let loginWindow = makeWindow(scene: scene!)
        let loginVC = LoginViewController()
        loginWindow.rootViewController = UINavigationController(rootViewController: loginVC)
        return loginWindow
    }
    
    private func makeContactRequiredWindow(message: String) -> UIWindow {
        let window = makeWindow(scene: scene!)
        window.rootViewController = ContactRequiredViewController(message: message)
        return window
    }
    
    private func showContactRequiredWindow(message: String) {
        postLoginGateCoordinator = nil
        dismissPostLoginGateWindow()
        showWindow(makeContactRequiredWindow(message: message))
    }

    func showMainContentWindow() {
        showWindow(tabBarWindow)
        if forceAssetsOnNextMainContent,
           let tabBarVC = tabBarWindow?.rootViewController as? MainTabBarViewController {
            tabBarVC.switchTo(indexPath: MainTabBarViewController.Path.assets)
            forceAssetsOnNextMainContent = false
        }
        IntercomConfig.appDidShowMainContent()
    }

    func onTermsCompletion() {
        showWindow(makeOnboardingWindow())
    }

    func onOnboardingCompletion() {
        // After onboarding, show login screen (user needs to authenticate)
        AuthLogger.info("Onboarding completed, showing login screen")
        showWindow(makeLoginWindow())
    }

    // userPassword can be nil if passcode is disabled
    func onEnterPasscodeCompletion(userPassword: String? = nil) {
        do {
            if AppConfiguration.FeatureToggles.securityCenter {
                try App.shared.securityCenter.unlockDataStore(userPassword: userPassword)
            }
            showPostLoginGateIfNeeded()
        } catch {
            LogService.shared.error("Failed to unlock", error: error)
        }
    }

    func onFaceIDCheckCompletion() {
        showPostLoginGateIfNeeded()
    }

    private func showPostLoginGateIfNeeded() {
        guard App.shared.authRepository.isAuthenticated() else {
            showMainContentWindow()
            return
        }
        
        // If the user is authenticated in Firebase Auth but not approved in the backend (lead gating),
        // we must not enter post-login gate (vault sync / pending vault activation screens).
        let currentUid = App.shared.authRepository.getCurrentUser()?.uid
        if provisioningGateApprovedUid != nil, provisioningGateApprovedUid == currentUid {
            // already approved for this uid in this session
        } else {
            guard !isCheckingProvisioningGate else { return }
            isCheckingProvisioningGate = true
            
            userProvisioningService.ensureUserRecord { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isCheckingProvisioningGate = false
                    
                    switch result {
                    case .success(let leadAction):
                        switch leadAction {
                        case .leadCreated:
                            let msg = NSLocalizedString("auth_lead_created_message", comment: "")
                            self.provisioningGateApprovedUid = nil
                            App.shared.authRepository.signOut { _ in
                                DispatchQueue.main.async {
                                    self.showContactRequiredWindow(message: msg)
                                }
                            }
                            return
                        case .leadMissingNames, .leadMissingCardManufacturer:
                            let msg = NSLocalizedString("auth_lead_pending_message", comment: "")
                            self.provisioningGateApprovedUid = nil
                            App.shared.authRepository.signOut { _ in
                                DispatchQueue.main.async {
                                    self.showContactRequiredWindow(message: msg)
                                }
                            }
                            return
                        default:
                            // allowed: existing_user / copied_from_lead / none
                            self.provisioningGateApprovedUid = currentUid
                        }
                    case .failure:
                        // Fail closed: if we can't verify approval, sign out and return to login.
                        self.provisioningGateApprovedUid = nil
                        App.shared.authRepository.signOut { _ in
                            DispatchQueue.main.async {
                                self.postLoginGateCoordinator = nil
                                self.dismissPostLoginGateWindow()
                                self.showWindow(self.makeLoginWindow())
                            }
                        }
                        return
                    }
                    
                    // Continue with the normal flow now that provisioning gate passed.
                    self.showPostLoginGateIfNeeded()
                }
            }
            return
        }

        if postLoginGateCoordinator != nil {
            if let postLoginGateWindow {
                showWindow(postLoginGateWindow)
            }
            return
        }

        let coordinator = PostLoginGateCoordinator(sceneDelegate: self)
        postLoginGateCoordinator = coordinator
        coordinator.start { [weak self] in
            guard let self else { return }
            self.postLoginGateCoordinator = nil
            self.showMainContentWindow()
        }
    }

    func showPostLoginGateWindow(rootViewController: UIViewController) {
        if postLoginGateWindow == nil {
            let window = makeWindow(scene: scene!)
            window.rootViewController = rootViewController
            postLoginGateWindow = window
        } else {
            postLoginGateWindow?.rootViewController = rootViewController
        }
        showWindow(postLoginGateWindow)
    }

    func dismissPostLoginGateWindow() {
        postLoginGateWindow?.isHidden = true
        postLoginGateWindow = nil
    }

    func onTabBarAppearance(of tabBar: MainTabBarViewController) {
        if startedFromNotification, let safeTxHash = App.shared.notificationHandler.transactionDetailsPayload {
            // present transaction details
            App.shared.notificationHandler.transactionDetailsPayload = nil
            let vc = ViewControllerFactory.transactionDetailsViewController(safeTxHash: safeTxHash)
            tabBar.present(vc, animated: true, completion: nil)

        } else if App.shared.notificationHandler.needsToRequestNotificationPermission {
            App.shared.notificationHandler.requestUserPermissionAndRegister()

        } else {
            App.shared.appReview.pullAppReviewTrigger()
        }
    }

    @objc private func handlePasscodeRequired(_ notification: Notification) {
        guard let task = notification.userInfo?["accessTask"] as? (_ password: String?) -> Void else {
            return
        }

        DispatchQueue.main.async { [unowned self] in
            showWindow(makeEnterPasscodeWindow(showsCloseButton: true) { result in
                switch result {
                case .success(let password):
                    task(password)
                case .close:
                    return
                }
            })
        }
    }
}

extension SceneDelegate: NavigationRouter {
    func routeFrom(from url: URL) -> NavigationRoute? {
        nil
    }
    
    func canNavigate(to route: NavigationRoute) -> Bool {
        guard let tabWindow = tabBarWindow, let tabBarVC = tabWindow.rootViewController as? MainTabBarViewController else { return false }
        return tabBarVC.canNavigate(to: route)
    }

    func navigate(to route: NavigationRoute) {
        guard let tabWindow = tabBarWindow, let tabBarVC = tabWindow.rootViewController as? MainTabBarViewController else { return }
        tabBarVC.navigate(to: route)
    }
}

// Window that can keep some view always on top of other views
class WindowWithViewOnTop: UIWindow {

    private weak var keepInFront: UIView?

    func addSubviewAlwaysOnTop(_ view: UIView) {
        keepInFront = view
        addSubview(view)
    }

    override func addSubview(_ view: UIView) {
        super.addSubview(view)
        if let v = keepInFront {
            bringSubviewToFront(v)
        }
    }
}
