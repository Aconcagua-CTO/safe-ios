//
//  MainTabBarViewController.swift
//  Multisig
//
//  Created by Moaaz on 3/25/21.
//  Copyright © 2021 Gnosis Ltd. All rights reserved.
//

import UIKit
import WhatsNewKit

class MainTabBarViewController: UITabBarController, UITabBarControllerDelegate {
    var onFirstAppear: (_ vc: MainTabBarViewController) -> Void = { _ in
    }

    private let tabIconSize = CGSize(width: 28, height: 28)
    private var appearsFirstTime: Bool = true
    private var addOwnerFlow: UpdateOwnersFromInviteLinkFlow!
    private var addSafeFlow: AddSafeFlow!
    private var createSafeFlow: CreateSafeFlow!
    
    // In-memory queue of incoming requests to present. Due to limitation of UIKit,
    // only one view controller can be presented at the same time.
    fileprivate var requestQueue: [WebConnectionRequest] = []
    fileprivate var debounceTimer: Timer?
    fileprivate var presentingRequest: Bool = false

    enum Path {
        static let assets: IndexPath = [0]
        static let balances: IndexPath = assets

        static let invertir: IndexPath = [1]

        static let pagar: IndexPath = [2]

        static let pedir: IndexPath = [3]

        static let settings: IndexPath = [4]
        static let appSettings: IndexPath = settings.appending(0)
        static let safeSettings: IndexPath = settings.appending(1)
        static let dappsSettings: IndexPath = settings.appending(2)

        static let queueSegment = 0
        static let historySegment = 1

        static let count = [assets, invertir, pagar, pedir, settings].count
    }

    lazy var balancesTabVC: BalancesUINavigationController = {
        balancesTabViewController()
    }()

    lazy var invertirTabVC: UIViewController = {
        invertirTabViewController()
    }()

    lazy var settingsTabVC: SettingsUINavigationController = {
        settingsTabViewController()
    }()

    lazy var pedirTabVC: UIViewController = {
        pedirTabViewController()
    }()

    lazy var pagarTabVC: UIViewController = {
        pagarTabViewController()
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self
        LogService.shared.debug("[Tabs] MainTabBar viewDidLoad")

        tabBar.isTranslucent = false
        tabBar.barTintColor = .backgroundSecondary
        tabBar.backgroundColor = .backgroundSecondary

        updateTabs()
        LogService.shared.debug("[Tabs] configured viewControllers=\(viewControllers?.map { String(describing: type(of: $0)) }.joined(separator: ", ") ?? "nil") selectedIndex=\(selectedIndex)")

        let notificationCenter = NotificationCenter.default

        notificationCenter.addObserver(
            self,
            selector: #selector(showHistoryTransactions),
            name: .incommingTxNotificationReceived,
            object: nil)

        notificationCenter.addObserver(
            self,
            selector: #selector(showQueuedTransactions),
            name: .queuedTxNotificationReceived,
            object: nil)

        notificationCenter.addObserver(
            self,
            selector: #selector(handleConfirmTransactionNotificationReceived),
            name: .confirmationTxNotificationReceived,
            object: nil)
        
        notificationCenter.addObserver(
            self,
            selector: #selector(handleInitiateTransactionNotificationReceived),
            name: .initiateTxNotificationReceived,
            object: nil)

        notificationCenter.addObserver(
            self,
            selector: #selector(handleSafeCreated),
            name: .safeCreationUpdate,
            object: nil)

        notificationCenter.addObserver(
            self,
            selector: #selector(handleDataRemoved),
            name: .passcodeDeleted,
            object: nil)

        WebConnectionController.shared.attach(observer: self)
    }

    deinit {
        WebConnectionController.shared.detach(observer: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard appearsFirstTime else {
            return
        }
        appearsFirstTime = false

        onFirstAppear(self)

        if let whatsNewVC = WhatsNewHandler().whatsNewViewController {
            present(whatsNewVC, animated: true)
        }

        WebConnectionController.shared.reconnect()

        presentDelayedControllers()
    }

    private func balancesTabViewController() -> BalancesUINavigationController {
        
        let assetsVC = AssetsViewController()

        let noSafesVC = AssetsNoSafesGateViewController()
        let loadSafeViewController = LoadSafeViewController()
        loadSafeViewController.trackingEvent = .assetsNoSafe

        let deploySafeVC = SafeDeployingViewController()

        let ribbonVC = RibbonViewController(rootViewController: assetsVC)
        noSafesVC.hasSafeViewController = ribbonVC
        noSafesVC.noSafeViewController = loadSafeViewController

        noSafesVC.safeDepolyingViewContoller = ViewControllerFactory.ribbonWith(viewController: deploySafeVC)
        let tabRoot = HeaderViewController(rootViewController: noSafesVC)
        let balances = balancesTabViewController(
            root: tabRoot,
            title: "Guardar",
            image: UIImage(named: "tab-icon-balances")!.scaled(to: tabIconSize),
            tag: Path.balances[0]
        )
        balances.assetsViewController = assetsVC

        return balances
    }

    private func transactionsRootViewController(selectedSegment: Int) -> UIViewController {
        let queuedTransactionsViewController = QueuedTransactionsViewController()
        let historyTransactionsViewController = HistoryTransactionsViewController()

        let segmentVC = SegmentViewController(namedClass: nil)
        segmentVC.segmentItems = [
            SegmentBarItem(image: UIImage(named: "ico-queued-transactions")!, title: "QUEUE"),
            SegmentBarItem(image: UIImage(named: "ico-history-transactions")!, title: "HISTORY")
        ]
        segmentVC.viewControllers = [
            queuedTransactionsViewController,
            historyTransactionsViewController
        ]
        segmentVC.selectedIndex = selectedSegment

        let noSafesVC = NoSafesViewController()
        let loadSafeViewController = LoadSafeViewController()
        let deploySafeVC = SafeDeployingViewController()

        loadSafeViewController.trackingEvent = .transactionsNoSafe
        let ribbonVC = RibbonViewController(rootViewController: segmentVC)
        noSafesVC.hasSafeViewController = ribbonVC
        noSafesVC.noSafeViewController = loadSafeViewController
        noSafesVC.safeDepolyingViewContoller = ViewControllerFactory.ribbonWith(viewController: deploySafeVC)

        let tabRoot = HeaderViewController(rootViewController: noSafesVC)
        return tabRoot
    }

    private func invertirTabViewController() -> UIViewController {
        let invertirVC = InvertirViewController()

        let noSafesVC = NoSafesViewController()
        let loadSafeViewController = LoadSafeViewController()
        loadSafeViewController.trackingEvent = .assetsNoSafe

        let deploySafeVC = SafeDeployingViewController()

        let ribbonVC = RibbonViewController(rootViewController: invertirVC)
        noSafesVC.hasSafeViewController = ribbonVC
        noSafesVC.noSafeViewController = loadSafeViewController
        noSafesVC.safeDepolyingViewContoller = ViewControllerFactory.ribbonWith(viewController: deploySafeVC)

        let tabRoot = HeaderViewController(rootViewController: noSafesVC)
        return tabViewController(
            root: tabRoot,
            title: "Invertir",
            image: UIImage(named: "tab-icon-invertir")!.withRenderingMode(.alwaysTemplate),
            tag: Path.invertir[0]
        )
    }

    private func settingsTabViewController() -> SettingsUINavigationController {
        let noSafesVC = NoSafesViewController()
        let loadSafeViewController = LoadSafeViewController()
        let deploySafeVC = SafeDeployingViewController()
        let safeSettingsVC = SafeSettingsViewController()
        let dappsVC = DappsViewController(namedClass: nil)
        
        loadSafeViewController.trackingEvent = .settingsSafeNoSafe
        noSafesVC.hasSafeViewController = safeSettingsVC
        noSafesVC.noSafeViewController = loadSafeViewController
        noSafesVC.safeDepolyingViewContoller = deploySafeVC

        let dappsNoSafesVC = NoSafesViewController()
        let dappsLoadSafeViewController = LoadSafeViewController()
        dappsLoadSafeViewController.trackingEvent = .dappsNoSafe
        let dappsDeploySafeVC = SafeDeployingViewController()

        dappsNoSafesVC.hasSafeViewController = dappsVC
        dappsNoSafesVC.noSafeViewController = dappsLoadSafeViewController
        dappsNoSafesVC.safeDepolyingViewContoller = dappsDeploySafeVC

        let appSettingsVC = AppSettingsViewController()

        let segmentVC = SegmentViewController(namedClass: nil)
        segmentVC.showsSegmentBar = App.configuration.services.environment.isDevelopment
        
        if App.configuration.services.environment.isDevelopment {
            // Development environment (Debug + Release): show all tabs
            segmentVC.segmentItems = [
                SegmentBarItem(image: UIImage(named: "ico-app-settings")!, title: "App Settings"),
                SegmentBarItem(image: UIImage(named: "ico-safe-settings")!, title: "My Safe Account"),
                SegmentBarItem(image: UIImage(named: "tab-icon-dapps")!, title: "Dapps")
            ]
            segmentVC.viewControllers = [
                appSettingsVC,
                noSafesVC,
                dappsNoSafesVC
            ]
        } else {
            // Staging/Production (Debug + Release): only show App Settings
            segmentVC.segmentItems = [
                SegmentBarItem(image: UIImage(named: "ico-app-settings")!, title: "App Settings")
            ]
            segmentVC.viewControllers = [
                appSettingsVC
            ]
        }
        segmentVC.selectedIndex = Path.appSettings.last
        let ribbonVC = RibbonViewController(rootViewController: segmentVC)
        
        let tabRoot = HeaderViewController(rootViewController: ribbonVC)
        let settingsTabVC = settingsTabViewController(
            root: tabRoot,
            title: "Más",
            image: UIImage(systemName: "line.3.horizontal")!.withRenderingMode(.alwaysTemplate),
            tag: Path.settings[0]
        )
        settingsTabVC.segmentViewController = segmentVC
        settingsTabVC.appSettingsViewController = appSettingsVC
        settingsTabVC.safeSettingsViewController = safeSettingsVC
        return settingsTabVC
    }

    private func pedirTabViewController() -> UIViewController {
        let pedirVC = ComingSoonViewController(title: "Pedir")

        let noSafesVC = NoSafesViewController()
        let loadSafeViewController = LoadSafeViewController()
        loadSafeViewController.trackingEvent = .assetsNoSafe

        let deploySafeVC = SafeDeployingViewController()

        let ribbonVC = RibbonViewController(rootViewController: pedirVC)
        noSafesVC.hasSafeViewController = ribbonVC
        noSafesVC.noSafeViewController = loadSafeViewController
        noSafesVC.safeDepolyingViewContoller = ViewControllerFactory.ribbonWith(viewController: deploySafeVC)

        let tabRoot = HeaderViewController(rootViewController: noSafesVC)
        return tabViewController(
            root: tabRoot,
            title: "Pedir",
            image: UIImage(named: "tab-icon-coins")!,
            tag: Path.pedir[0]
        )
    }

    private func pagarTabViewController() -> UIViewController {
        let pagarVC = ComingSoonViewController(title: "Pagar")

        let noSafesVC = NoSafesViewController()
        let loadSafeViewController = LoadSafeViewController()
        loadSafeViewController.trackingEvent = .assetsNoSafe

        let deploySafeVC = SafeDeployingViewController()

        let ribbonVC = RibbonViewController(rootViewController: pagarVC)
        noSafesVC.hasSafeViewController = ribbonVC
        noSafesVC.noSafeViewController = loadSafeViewController
        noSafesVC.safeDepolyingViewContoller = ViewControllerFactory.ribbonWith(viewController: deploySafeVC)

        let tabRoot = HeaderViewController(rootViewController: noSafesVC)
        return tabViewController(
            root: tabRoot,
            title: "Pagar",
            image: UIImage(named: "tab-icon-dapps")!,
            tag: Path.pagar[0]
        )
    }

    private func balancesTabViewController(root: UIViewController, title: String, image: UIImage, tag: Int) -> BalancesUINavigationController {
        let nav = BalancesUINavigationController(rootViewController: root)
        let tabItem = UITabBarItem(title: title, image: image, tag: tag)
        nav.tabBarItem = tabItem
        return nav
    }

    private func settingsTabViewController(root: UIViewController, title: String, image: UIImage, tag: Int) -> SettingsUINavigationController {
        let nav = SettingsUINavigationController(rootViewController: root)
        let tabItem = UITabBarItem(title: title, image: image, tag: tag)
        nav.tabBarItem = tabItem
        nav.showBadge()
        return nav
    }

    private func tabViewController(root: UIViewController, title: String, image: UIImage, tag: Int) -> UIViewController {
        let nav = UINavigationController(rootViewController: root)
        let tabItem = UITabBarItem(title: title, image: image, tag: tag)
        nav.tabBarItem = tabItem
        return nav
    }
    
    @objc private func handleInitiateTransactionNotificationReceived(_ notification: Notification) {
        if let transactionDetails = notification.userInfo?["transactionDetails"] as? SCGModels.TransactionDetails {
            showTransactionDetails(transactionDetails: transactionDetails)
        } else {
            showQueuedTransactions()
        }
    }

    @objc private func showQueuedTransactions() {
        openTransactions(segment: Path.queueSegment)
    }

    @objc private func showHistoryTransactions() {
        openTransactions(segment: Path.historySegment)
    }
    
    @objc private func updateTabs() {
        viewControllers = [balancesTabVC, invertirTabVC, pagarTabVC, pedirTabVC, settingsTabVC]
        LogService.shared.debug("[Tabs] updateTabs() set viewControllers count=\(viewControllers?.count ?? -1) selectedIndex=\(selectedIndex)")
    }

    @objc func handleConfirmTransactionNotificationReceived(_ notification: Notification) {
        guard let safeTxHash = App.shared.notificationHandler.transactionDetailsPayload else { return }
        App.shared.notificationHandler.transactionDetailsPayload = nil
        showTransactionDetails(safeTxHash: safeTxHash)
    }
    
    @objc private func handleSafeCreated(_ notification: Notification) {
        // get mode, txHash, and safe if creation successful from the notification
        if let isSuccess = notification.userInfo?["success"] as? Bool,
           let safe = notification.userInfo?["safe"] as? Safe {
            if safe.isSelected && presentedViewController == nil {
                if isSuccess {
                    presentSuccessDeployment(safe: safe)
                } else {
                    presentFailedDeployment(safe: safe)
                }
            } else {
                SafeDeploymentNotificationController.sendNotification(safe: safe)
            }
        }
    }

    @objc private func handleDataRemoved(_ notification: Notification) {
        if presentedViewController != nil {
            dismiss(animated: true)
        }
    }

    private func presentSuccessDeployment(safe: Safe) {
        SafeDeploymentFinishedViewController.present(
            presenter: self,
            mode: .success,
            chain: safe.chain!,
            txHash: nil,
            safe: safe,
            onClose: { },
            onRetry: { })
    }

    private func presentFailedDeployment(safe: Safe) {
        let params = SafeCreationCall.by(safe: safe).first
        let txHash = params?.transactionHash
        SafeDeploymentFinishedViewController.present(
            presenter: self,
            mode: .failure,
            chain: safe.chain!,
            txHash: txHash,
            safe: safe,
            onClose: {
                Safe.remove(safe: safe)
            },
            onRetry: { [weak self] in
                Tracker.trackEvent(.createSafeRetry)
                let createSafeVC = CreateSafeViewController()
                createSafeVC.txHash = txHash
                if let chain = safe.chain {
                    createSafeVC.chain = chain
                }
                createSafeVC.onClose = { [weak self] in
                    self?.dismiss(animated: true, completion: nil)
                }
                let vc = ViewControllerFactory.modal(viewController: createSafeVC)
                self?.present(vc, animated: true)
            })
    }

    private func showTransactionDetails(transactionId: String) {
        let vc = ViewControllerFactory.transactionDetailsViewController(transactionId: transactionId)
        presentWhenReady(vc)
    }

    private func showTransactionDetails(safeTxHash: Data) {
        let vc = ViewControllerFactory.transactionDetailsViewController(safeTxHash: safeTxHash)
        presentWhenReady(vc)
    }
    
    private func showTransactionDetails(transactionDetails: SCGModels.TransactionDetails) {
        let vc = ViewControllerFactory.transactionDetailsViewController(transaction: transactionDetails)
        presentWhenReady(vc)
    }

    private var delayedPresentationViewController: UIViewController?

    private func presentWhenReady(_ vc: UIViewController) {
        if view.window == nil {
            delayedPresentationViewController = vc
        } else if presentedViewController == nil {
            present(vc, animated: true)
        } else {
            dismiss(animated: true) { [unowned self] in
                present(vc, animated: true)
            }
        }
    }

    private func presentDelayedControllers() {
        if let vc = delayedPresentationViewController, presentedViewController == nil, view.window != nil {
            present(vc, animated: true)
            delayedPresentationViewController = nil
        }
    }
}

extension MainTabBarViewController: NavigationRouter {
    func routeFrom(from url: URL) -> NavigationRoute? {
        nil
    }
    
    func canNavigate(to route: NavigationRoute) -> Bool {
        if route.path.starts(with: "/settings/") {
            return true
        } else if route.path.starts(with: "/transactions/") {
            return true
        } else if route.path == NavigationRoute.showAssets().path {
            return true
        } else if route.path == NavigationRoute.deploymentFailedPath {
            return true
        } else if route.path == NavigationRoute.requestToAddOwnerPath {
            return true
        } else if route.path == NavigationRoute.loadSafe().path {
            return true
        } else if route.path == NavigationRoute.createSafe().path {
            return true
        } else if route.path == NavigationRoute.dapps().path {
            return true
        }

        return false
    }

    func navigate(to route: NavigationRoute) {
        if route.path.starts(with: "/settings/") {
            selectSafe(from: route)
            
            if route.path == NavigationRoute.appSettings().path {
                switchTo(indexPath: Path.appSettings)
            } else if route.path == NavigationRoute.accountSettingsPath {
                switchTo(indexPath: Path.safeSettings)
            } else if route.path == NavigationRoute.accountAdvancedSettingsPath {
                switchTo(indexPath: Path.safeSettings)
                
                if let safeSettingsVC = settingsTabVC.safeSettingsViewController {
                    safeSettingsVC.navigateAfterDelay(to: route)
                }
            } else if NavigationRoute.appSettingsDetailPaths.contains(route.path) {
                switchTo(indexPath: Path.appSettings)
                
                if let appSettingsVC = settingsTabVC.appSettingsViewController {
                    appSettingsVC.navigateAfterDelay(to: route)
                }
            }

        } else if route.path.starts(with: "/transactions/") {
            if let rawAddress = route.info["address"] as? String,
               let rawChainId = route.info["chainId"] as? String {
                guard let safe = Safe.by(address: rawAddress, chainId: rawChainId) else {
                    // don't navigate, exit because the route can't work.
                    return
                }
                if !safe.isSelected {
                    safe.select()
                }
                if let transactionId = route.info["transactionId"] as? String {
                    showTransactionDetails(transactionId: transactionId)
                } else if route.path.contains("history") {
                    openTransactions(segment: Path.historySegment)
                } else {
                    openTransactions(segment: Path.queueSegment)
                }
            }
        } else if route.path == NavigationRoute.showAssets().path {
            guard selectSafe(from: route) else { return }
            switchTo(indexPath: Path.balances)
        } else if route.path == NavigationRoute.deploymentFailedPath {
            presentFailedDeployment(safe: route.info["safe"] as! Safe)
        } else if route.path == NavigationRoute.requestToAddOwnerPath {
            let parameters = route.info["parameters"] as! AddOwnerRequestParameters

            addOwnerFlow = UpdateOwnersFromInviteLinkFlow(parameters: parameters) { [unowned self] _ in
                addOwnerFlow = nil
                dismiss(animated: true)
            }

            present(flow: addOwnerFlow)
        } else if route.path == NavigationRoute.loadSafe().path {
            Tracker.trackEvent(.addSafeFromURL)

            let chain = route.info["chainId"] as? String
            let address = route.info["address"] as? String
            addSafeFlow = AddSafeFlow(chainId: chain, address: address, completion: { [weak self] _ in
                self?.addSafeFlow = nil
            })
            present(flow: addSafeFlow)
        } else if route.path == NavigationRoute.createSafe().path {
            Tracker.trackEvent(.createSafeFromURL)
            
            let chain = route.info["chainId"] as? String
            
            createSafeFlow = CreateSafeFlow(chainId: chain, completion: { [weak self] _ in
                self?.createSafeFlow = nil
            })
            
            present(flow: createSafeFlow)
        } else if route.path == NavigationRoute.dapps().path {
            selectSafe(from: route)
            switchTo(indexPath: Path.dappsSettings)
        } else if route.path.starts(with: "/pedir/") {
            switchTo(indexPath: Path.pedir)
        }
    }
    
    
    // if there is address and chain id, then switch to that safe.
    //      if such safe doesn't exist, then do nothing.
    // if no parameters passed, just switch to balances.
    @discardableResult
    private func selectSafe(from route: NavigationRoute) -> Bool {
        if let address = route.info["address"] as? String,
           let chainId = route.info["chainId"] as? String,
           let safe = Safe.by(address: address, chainId: chainId),
           !safe.isSelected {
            safe.select()
            return true
        }
        return false
    }

    func switchTo(indexPath: IndexPath) {
        var indexPath = indexPath

        guard !indexPath.isEmpty else { return }
        let index = indexPath.removeFirst()

        guard index < Path.count else { return }
        switchTab(index: index)

        guard !indexPath.isEmpty else { return }
        let segment = indexPath.removeFirst()

        switch index {
        case Path.assets.first:
            switchAssets(segment: segment)

        case Path.invertir.first:
            break

        case Path.settings.first:
            switchSettings(segment: segment)

        case Path.pedir.first:
            break

        case Path.pagar.first:
            break

        default:
            break
        }
    }

    func openTransactions(segment: Int) {
        guard segment == Path.queueSegment || segment == Path.historySegment else { return }
        guard let nav = selectedViewController as? UINavigationController else { return }

        let root = transactionsRootViewController(selectedSegment: segment)
        root.hidesBottomBarWhenPushed = false
        nav.pushViewController(root, animated: true)
    }

    func switchTab(index: Int) {
        guard let vcs = viewControllers, index < vcs.count, index != selectedIndex else { return }
        let from = selectedIndex
        selectedIndex = index
        LogService.shared.debug("[Tabs] switchTab from=\(from) to=\(index) vc=\(String(describing: type(of: vcs[index])))")
    }

    // MARK: - UITabBarControllerDelegate

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        LogService.shared.debug("[Tabs] didSelect index=\(tabBarController.selectedIndex) vc=\(String(describing: type(of: viewController)))")
    }

    func switchAssets(segment: Int) { }

    func switchSettings(segment: Int) {
        guard let segmentVC = settingsTabVC.segmentViewController, segment < segmentVC.segmentItems.count else {
            return
        }
        segmentVC.selectSegment(at: segment)
    }
}

class SettingsUINavigationController: UINavigationController {
    weak var segmentViewController: SegmentViewController?
    weak var appSettingsViewController: AppSettingsViewController?
    weak var safeSettingsViewController: SafeSettingsViewController?

    override init(rootViewController: UIViewController) {
        super.init(rootViewController: rootViewController)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showBadge),
            name: NSNotification.Name.IntercomUnreadConversationCountDidChange,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showBadge),
            name: NSNotification.Name.didReadConnectToWebBanner,
            object: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    var shouldShowBadge: Bool {
        IntercomConfig.unreadConversationCount() > 0 ||
            AppSettingsViewController.shouldBringAttentionToDesktopPairing()
    }
    
    @objc func showBadge() {
        if shouldShowBadge {
            tabBarItem.badgeValue = ""
            tabBarItem.badgeColor = UIColor.warning
        } else {
            tabBarItem.badgeValue = nil
        }
    }
}

class BalancesUINavigationController: UINavigationController {
    weak var assetsViewController: AssetsViewController?
}


extension MainTabBarViewController: WebConnectionRequestObserver {
    func didUpdate(request: WebConnectionRequest) {
        guard request.status == .pending else { return }
        requestQueue.append(request)
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false, block: { [weak self] _ in
            self?.presentRequests()
        })
    }

    /// Presents next request from the queue.
    /// The way how UIKit presentation works is that you can present only one
    /// screen at the same time, and you can't present another one during any presentation animation.
    /// That's why we queue the requests and open next from the queue when the current one is closed.
    func presentRequests() {
        guard !requestQueue.isEmpty && !presentingRequest else { return }
        let request = requestQueue.removeLast()

        // need to skip the requests that are retained in memory but for which connection is closed.
        // otherwise the view controllers would crash (they expect the connection to be opened)
        guard let connection = WebConnectionController.shared.connection(for: request), connection.status == .opened else {
            presentRequests()
            return
        }

        presentingRequest = true
        let completion: () -> Void = { [weak self] in
            self?.presentingRequest = false
            self?.presentRequests()
        }

        switch request {
        case let signRequest as WebConnectionSignatureRequest:
            let vc = SignatureRequestViewController()
            present(controller: vc, request: signRequest, completion: completion)

        case let txRequest as WebConnectionSendTransactionRequest:
            let vc = SendTransactionRequestViewController()
            present(controller: vc, request: txRequest, completion: completion)

        default:
            presentingRequest = false
            presentRequests()
            break
        }
    }

    fileprivate func present<T, R>(controller: T, request: R, completion: @escaping () -> Void) where T: WebRequestViewController, T: UIViewController, T.Request == R, R: WebConnectionRequest {
        controller.request = request
        controller.controller = WebConnectionController.shared
        controller.connection = WebConnectionController.shared.connection(for: request)
        controller.onFinish = { [weak self] in
            self?.dismiss(animated: true, completion: completion)
        }
        let vc = ViewControllerFactory.modal(viewController: controller)

        if let existing = presentedViewController {
            existing.dismiss(animated: true) { [unowned self] in
                present(vc, animated: true)
            }
        } else {
            present(vc, animated: true)
        }
    }
}

protocol WebRequestViewController: AnyObject {
    associatedtype Request
    var request: Request! { get set }
    var controller: WebConnectionController! { get set }
    var connection: WebConnection! { get set }
    var onFinish: () -> Void { get set }
}

extension SignatureRequestViewController: WebRequestViewController {}

extension SendTransactionRequestViewController: WebRequestViewController {}
