//
//  AppSettingsViewController.swift
//  Multisig
//
//  Created by Andrey Scherbovich on 10.11.20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import UIKit
import SwiftUI

fileprivate protocol SectionItem {}

class AppSettingsViewController: UITableViewController, PasscodeProtecting {
    var notificationCenter = NotificationCenter.default
    var app = App.configuration.app
    var legal = App.configuration.legal
    private static let vaultListTitle = "Bóvedas"

    private let tableBackgroundColor: UIColor = .backgroundPrimary
    private let sectionHeaderHeight: CGFloat = 28
    private var sections = [SectionItems]()

    private typealias SectionItems = (section: Section, items: [SectionItem])
    
    private var exportFlow: ExportDataFlow!
    private var importFlow: ImportDataFlow!

    enum Section {
        case app
        case support(String)
        case advanced(String)
        case about(String)

        enum App: SectionItem {
            case vaultList(String)
            case desktopPairing(String)
            case ownerKeys(String, Bool, String)
            case addressBook(String)
            case passcode(String)
            case fiat(String, String)
            case chainPrefix(String)
            case appearance(String)
            case experimental(String)
            case herencia(String)
            case seguridad(String)
            case planes(String)
            case logout(String)
            case logoutAndReset(String)
        }
        
        enum Support: SectionItem {
            case chatWithUs(String)
            case getSupport(String)
        }
        
        enum Advanced: SectionItem {
            case advanced(String)
            case toggles(String)
            case dataExport(String)
            case dataImport(String)
        }

        enum About: SectionItem {
            case aboutGnosisSafe(String)
            case appVersion(String, String)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = tableBackgroundColor
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 68
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        } else {
            // Fallback on earlier versions
        }

        tableView.separatorStyle = .singleLine

        tableView.registerCell(BasicCell.self)
        tableView.registerCell(InfoCell.self)
        tableView.registerHeaderFooterView(BasicHeaderView.self)

        buildSections()

        addObservers()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Tracker.trackEvent(.settingsApp)
        reload()
    }

    private func buildSections() {
        sections = []
        var appSection: (section: AppSettingsViewController.Section, items: [SectionItem]) = (section: .app, items: [])
        
        appSection.items.append(contentsOf: [
            Section.App.vaultList(Self.vaultListTitle),
            Section.App.ownerKeys("Llaves", !KeyInfo.keysWithoutBackup().isEmpty, "\(KeyInfo.count())"),
            Section.App.addressBook("Agenda"),
            Section.App.herencia("Herencia"),
            Section.App.seguridad("Seguridad"),
            Section.App.planes("Planes")
        ])

        appSection.items.append(Section.Support.chatWithUs("Ayuda"))
        if FirebaseRemoteConfig.shared.boolValue(key: .connectToWebDiscontinued) != true {
            appSection.items.append(Section.App.desktopPairing("Wallet connect"))
        }
        
        // Show these settings in Development environment only (Debug + Release)
        if App.configuration.services.environment.isDevelopment {
            appSection.items.append(contentsOf: [
                Section.App.passcode("Security"),
                Section.App.fiat("Fiat currency", AppSettings.selectedFiatCode),
                Section.App.chainPrefix("Chain prefix"),
                Section.App.appearance("Appearance")
            ])
        }
        
        // Add logout option if user is authenticated
        if App.shared.authRepository.isAuthenticated() {
            appSection.items.append(Section.App.logout("Sign Out"))
            if App.configuration.services.environment.isDevelopment {
                appSection.items.append(Section.App.logoutAndReset("Sign Out & Reset"))
            }
        }
        
        let supportSection: (section: AppSettingsViewController.Section, items: [SectionItem]) = (section: .support("Support & Feedback"), items: [])
        var advancedSection: (section: AppSettingsViewController.Section, items: [SectionItem]) = (section: .advanced("Advanced"), items: [
            Section.Advanced.advanced("Advanced"),
            Section.Advanced.dataExport("Export data"),
            Section.Advanced.dataImport("Import data")
        ])
        
        if App.configuration.services.environment.isDevelopment {
            advancedSection.items.append(
                Section.Advanced.toggles("Feature Toggles")
            )
        }

        let aboutSectionTitle = App.configuration.services.environment.isDevelopment ? "About" : "Acerca de"
        let aboutSafeTitle = App.configuration.services.environment.isDevelopment ? "About Safe{Wallet}" : "Acerca de Bóveda"
        let appVersionTitle = App.configuration.services.environment.isDevelopment ? "App version" : "Versión"
        let aboutSection: (section: AppSettingsViewController.Section, items: [SectionItem]) = (section: .about(aboutSectionTitle), items: [
            Section.About.aboutGnosisSafe(aboutSafeTitle),
            Section.About.appVersion(appVersionTitle, "\(app.marketingVersion) (\(app.buildVersion))"),
        ])
        sections += [
            appSection,
            aboutSection
        ]
        if App.configuration.services.environment.isDevelopment {
            sections.append(advancedSection)
        }
        if !supportSection.items.isEmpty {
            sections.insert(supportSection, at: 1)
        }
    }

    @objc func hidePresentedController() {
        reload()
    }

    // MARK: - Actions

    @objc private func reload() {
        buildSections()
        tableView.reloadData()
    }

    private func addObservers() {
        for notification in [Notification.Name.ownerKeyRemoved,
                             .ownerKeyImported,
                             .ownerKeyBackedUp,
                             .selectedFiatCurrencyChanged,
                             .updatedExperemental,
                             .IntercomUnreadConversationCountDidChange,
                             .didReadConnectToWebBanner] {
            notificationCenter.addObserver(
                self,
                selector: #selector(reload),
                name: notification,
                object: nil)
        }
    }

    @discardableResult
    private func showDesktopPairing() -> WebConnectionsViewController? {
        if let vc = navigationTop(as: WebConnectionsViewController.self) {
            return vc
        } else {
            popNavigationStack()
        }
        
        let keys = WebConnectionController.shared.accountKeys()
        if keys.isEmpty {
            let addOwnersVC = AddOwnerFirstViewController()
            addOwnersVC.descriptionText = "To connect to Safe{Wallet} import at least one owner key. Keys are used to confirm transactions."
            addOwnersVC.onSuccess = { [weak self] in
                self?.dismiss(animated: true) {
                    _ = self?.showDesktopPairing()
                }
            }
            let nav = UINavigationController(rootViewController: addOwnersVC)
            present(nav, animated: true)
            return nil
        } else {
            let connectionsVC = WebConnectionsViewController()
            show(connectionsVC, sender: self)
            return connectionsVC
        }
    }

    private func showOwnerKeys() {
        let vc = OwnerKeysListViewController()
        show(vc, sender: self)
    }

    private func presentVaultList() {
        let switchSafesVC: UIViewController
        if App.configuration.services.environment.isDevelopment {
            switchSafesVC = SwitchSafesViewController()
        } else {
            switchSafesVC = GroupedSwitchSafesViewController()
        }
        let nav = UINavigationController(rootViewController: switchSafesVC)
        present(nav, animated: true)
    }

    private func showAddressBook() {
        show(AddressBookListTableViewController(), sender: self)
    }

    private func openPasscode() {
        let vc = SecuritySettingsViewController()
        show(vc, sender: self)
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].items.count
    }

    static func shouldBringAttentionToDesktopPairing() -> Bool {
        !WebConnectionController.shared.accountKeys().isEmpty &&
            AppSettings.didShowDeprecateConnectToWeb != true &&
            FirebaseRemoteConfig.shared.boolValue(key: .connectToWebDiscontinued) != true
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = sections[indexPath.section].items[indexPath.row]
        switch item {

        case Section.App.vaultList(let name):
            return tableView.basicCell(name: name, icon: "tab-icon-balances", iconTintColor: .icon, indexPath: indexPath)
            
        case Section.App.desktopPairing(let name):
            return tableView.basicCell(
                name: name,
                icon: "tab-icon-dapps",
                iconTintColor: .icon,
                indexPath: indexPath,
                supplementaryImage: Self.shouldBringAttentionToDesktopPairing() ? UIImage(named: "ico-warning") : nil)
            
        case Section.App.ownerKeys(let name, let warning, let count):
            return tableView.basicCell(name: name,
                                       icon: "ico-app-settings-key",
                                       detail: count,
                                       indexPath: indexPath,
                                       supplementaryImage: warning ? UIImage(named: "ico-private-key") : nil)

        case Section.App.addressBook(let name):
            return tableView.basicCell(name: name, icon: "ico-app-settings-book", indexPath: indexPath)
            
        case Section.App.passcode(let name):
            return tableView.basicCell(name: name, icon: "ico-app-settings-lock", indexPath: indexPath)
            
        case Section.App.fiat(let name, let value):
            return tableView.basicCell(name: name, icon: "ico-app-settings-fiat", detail: value, indexPath: indexPath)

        case Section.App.chainPrefix(let name):
            return tableView.basicCell(name: name, icon: "ico-app-settings-hash", indexPath: indexPath)

        case Section.App.appearance(let name):
            return tableView.basicCell(name: name, icon: "ico-app-settings-moon", indexPath: indexPath)
    
        case Section.App.experimental(let name):
            return tableView.basicCell(name: name, icon: "ico-app-settings-package", indexPath: indexPath)
            
        case Section.App.herencia(let name):
            return tableView.basicCell(name: name, icon: "ico-app-settings-herencia", indexPath: indexPath)
            
        case Section.App.seguridad(let name):
            return tableView.basicCell(name: name, icon: "ico-app-settings-lock", indexPath: indexPath)
            
        case Section.App.planes(let name):
            return tableView.basicCell(name: name, icon: "ico-app-settings-desktop-pairing", indexPath: indexPath)
            
        case Section.App.logout(let name):
            return tableView.basicCell(name: name, icon: "ico-app-settings-lock", indexPath: indexPath)

        case Section.App.logoutAndReset(let name):
            return tableView.basicCell(name: name, icon: "ico-app-settings-lock", indexPath: indexPath)
            
        case Section.Support.chatWithUs(let name):
            if IntercomConfig.unreadConversationCount() > 0 {
                return tableView.basicCell(name: name,
                                           icon: "ico-app-settings-message-circle-with-badge",
                                           iconTintColor: .icon,
                                           indexPath: indexPath)
            } else {
                return tableView.basicCell(name: name,
                                           icon: "ico-app-settings-message-circle",
                                           iconTintColor: .icon,
                                           indexPath: indexPath)
            }

        case Section.Support.getSupport(let name):
            return tableView.basicCell(name: name, icon: "ico-app-settings-support", indexPath: indexPath)
            
        case Section.Advanced.advanced(let name):
            return tableView.basicCell(name: name, icon: nil, indexPath: indexPath)
            
        case Section.Advanced.dataExport(let name):
            return tableView.basicCell(name: name, icon: nil, indexPath: indexPath)
            
        case Section.Advanced.dataImport(let name):
            return tableView.basicCell(name: name, icon: nil, indexPath: indexPath)

        case Section.Advanced.toggles(let name):
            return tableView.basicCell(name: name, icon: nil, indexPath: indexPath)

        case Section.About.aboutGnosisSafe(let name):
            return tableView.basicCell(name: name, icon: nil, indexPath: indexPath)
            
        case Section.About.appVersion(let name, let version):
            return tableView.infoCell(name: name, info: version, indexPath: indexPath)

        default:
            return UITableViewCell()
        }
    }

    // MARK: - Table view delegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = sections[indexPath.section].items[indexPath.row]
        switch item {
        case Section.App.vaultList:
            presentVaultList()

        case Section.App.desktopPairing:
            showDesktopPairing()

        case Section.App.ownerKeys:
            showOwnerKeys()

        case Section.App.addressBook:
            showAddressBook()
            
        case Section.App.passcode:
            openPasscode()
            
        case Section.App.fiat:
            let selectFiatViewController = SelectFiatViewController()
            show(selectFiatViewController, sender: self)
            
        case Section.App.chainPrefix:
            show(ChainSettingsTableViewController(), sender: self)

        // HIDDEN: Appearance case handling hidden to force dark mode. To reverse, uncomment the block below.
        //case Section.App.appearance:
        //    let appearanceViewController = ChangeDisplayModeTableViewController()
        //    show(appearanceViewController, sender: self)

        case Section.App.experimental:
            let experimentalViewController = ExperimentalViewController()
            show(experimentalViewController, sender: self)
            
        case Section.App.herencia:
            let comingSoonVC = ComingSoonViewController()
            show(comingSoonVC, sender: self)
            
        case Section.App.seguridad:
            let comingSoonVC = ComingSoonViewController()
            show(comingSoonVC, sender: self)
            
        case Section.App.planes:
            let comingSoonVC = ComingSoonViewController()
            show(comingSoonVC, sender: self)
            
        case Section.App.logout:
            handleLogout()

        case Section.App.logoutAndReset:
            handleLogoutAndReset()
            
        case Section.Support.chatWithUs:
            Tracker.trackEvent(.userOpenIntercom)
            IntercomConfig.startChat()
            break
            
        case Section.Support.getSupport:
            let getInTouchVC = GetInTouchView()
            let hostingController = UIHostingController(rootView: getInTouchVC)
            show(hostingController, sender: self)
            
        case Section.Advanced.advanced:
            navigateToAdvancedAppSettings()
            
        case Section.Advanced.dataExport:
            showExport()

        case Section.Advanced.dataImport:
            showImport()

        case Section.Advanced.toggles:
            let togglesVC = FeatureToggleTableViewController()
            show(togglesVC, sender: self)
            
        case Section.About.aboutGnosisSafe:
            show(AboutGnosisSafeTableViewController(), sender: self)
            break

        default:
            break
        }
    }
    
    private func showExport() {
        authenticate(biometry: false) { [weak self] success in
            guard success, let self = self else { return }
            
            self.exportFlow = ExportDataFlow(completion: { [weak self] success in
                self?.exportFlow = nil
            })
            self.present(flow: self.exportFlow)
        }
    }
    
    private func showImport() {
        authenticate(biometry: false) { [weak self] success in
            guard success, let self = self else { return }
            
            self.importFlow = ImportDataFlow(completion: { [weak self] success in
                self?.importFlow = nil
            })
            self.present(flow: self.importFlow)
        }
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let section = sections[section].section
        let view = tableView.dequeueHeaderFooterView(BasicHeaderView.self)
        switch section {
        case Section.support(let name):
            view.setName(name)
            
        case Section.advanced(let name):
            view.setName(name)
            
        case Section.about(let name):
            view.setName(name)
            
        default:
            break
        }
        
        return view
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return BasicCell.rowHeight
    }
  
    override func tableView(_ tableView: UITableView, heightForHeaderInSection _section: Int) -> CGFloat {
        let section = sections[_section].section
        switch section {
        case .app:
            return 0
        default:
            return BasicHeaderView.headerHeight
        }
    }
}

extension AppSettingsViewController: NavigationRouter {
    func routeFrom(from url: URL) -> NavigationRoute? {
        nil
    }
    
    func canNavigate(to route: NavigationRoute) -> Bool {
        if App.configuration.services.environment.isDevelopment,
           route.path == NavigationRoute.connectToWeb().path,
           FirebaseRemoteConfig.shared.boolValue(key: .connectToWebDiscontinued) != true
        {
            return true
        }
        return false
    }

    func navigate(to route: NavigationRoute) {
        if route.path == NavigationRoute.appearanceSettings().path {
            navigateToAppearance()
        } else if
            route.path == NavigationRoute.connectToWeb().path &&
            FirebaseRemoteConfig.shared.boolValue(key: .connectToWebDiscontinued) != true
        {
            if App.configuration.services.environment.isDevelopment {
                navigateToConnectToWeb(route)
            }
        } else if route.path == NavigationRoute.advancedAppSettings().path {
            navigateToAdvancedAppSettings()
        } else if route.path == NavigationRoute.addressBook().path {
            navigateToAddressBook()
        } else if NavigationRoute.appSettingsAboutPaths.contains(route.path) {
            navigateToAbout(route)
        }
    }
    
    private func navigateToAbout(_ route: NavigationRoute) {
        var aboutVC: AboutGnosisSafeTableViewController
        if let vc = navigationTop(as: AboutGnosisSafeTableViewController.self) {
            aboutVC = vc
        } else {
            popNavigationStack()
            
            aboutVC = AboutGnosisSafeTableViewController()
            show(aboutVC, sender: self)
        }

        aboutVC.navigateAfterDelay(to: route)
    }
    
    private func navigateToAppearance() {
        if navigationTopIs(ChangeDisplayModeTableViewController.self) {
            return
        }
        
        popNavigationStack()
        
        let appearanceViewController = ChangeDisplayModeTableViewController()
        show(appearanceViewController, sender: self)
    }
    
    private func navigateToConnectToWeb(_ route: NavigationRoute) {
        guard FirebaseRemoteConfig.shared.boolValue(key: .connectToWebDiscontinued) != true else { return }
        if let pairingVC = showDesktopPairing() {
            pairingVC.navigateAfterDelay(to: route)
        }
    }
    
    private func navigateToAdvancedAppSettings() {
        if navigationTopIs(UIHostingController<AdvancedAppSettings>.self) {
            return
        }

        popNavigationStack()
        
        let advancedVC = AdvancedAppSettings()
        let hostingController = UIHostingController(rootView: advancedVC)
        show(hostingController, sender: self)
    }
    
    private func navigateToAddressBook() {
        if navigationTopIs(AddressBookListTableViewController.self) {
            return
        }
        
        popNavigationStack()
        
        showAddressBook()
    }
    
    private func handleLogout() {
        AuthLogger.info("User initiated logout from settings")
        
        // Show confirmation alert
        let alert = UIAlertController(
            title: "Sign Out",
            message: "Are you sure you want to sign out?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Sign Out", style: .destructive) { [weak self] _ in
            self?.performLogout()
        })
        
        present(alert, animated: true)
    }
    
    private func performLogout() {
        AuthLogger.info("Performing logout...")
        
        App.shared.authRepository.signOut { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success:
                    AuthLogger.success("Logout successful, showing login screen")
                    // Navigate to login screen via SceneDelegate
                    if let sceneDelegate = self.view.window?.windowScene?.delegate as? SceneDelegate {
                        sceneDelegate.onAppUpdateCompletion()
                    }
                case .failure(let error):
                    AuthLogger.error("Logout failed", error: error)
                    // Show error message
                    SnackbarViewController.show(
                        "Failed to sign out: \(error.localizedDescription)",
                        duration: 4.0
                    )
                }
            }
        }
    }

    private func handleLogoutAndReset() {
        AuthLogger.info("User initiated logout+reset from settings")

        let alert = UIAlertController(
            title: "Sign Out & Reset",
            message: "This will sign you out, reset Terms acceptance, remove local owner keys, and remove the local vault list from this device. Continue?",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Sign Out & Reset", style: .destructive) { [weak self] _ in
            self?.performLogoutAndReset()
        })

        present(alert, animated: true)
    }

    private func performLogoutAndReset() {
        AuthLogger.info("Performing logout+reset...")

        App.shared.authRepository.signOut { [weak self] result in
            guard let self = self else { return }

            DispatchQueue.main.async {
                switch result {
                case .success:
                    AuthLogger.success("Logout successful, clearing local state (terms, vaults, keys, session)")

                    // Must be on main thread (AppSetting wrapper enforces it)
                    AppSettings.termsAccepted = false
                    AppSettings.onboardingCompleted = false
                    AppSettings.companyId = nil
                    AppSettings.pendingOwnerKeysRegistration = false
                    AppSettings.importedOwnerKey = false

                    // Clear local vault list and owner keys so the app re-enters the "new user" path
                    // (GenerateKeyFlow / Tangem activation) without requiring reinstall.
                    try? Safe.removeAll()
                    try? OwnerKeyController.deleteAllKeys(showingMessage: false)

                    // Route to Terms (since termsAccepted is now false)
                    if let sceneDelegate = self.view.window?.windowScene?.delegate as? SceneDelegate {
                        sceneDelegate.onAppUpdateCompletion()
                    }

                case .failure(let error):
                    AuthLogger.error("Logout+reset failed (no data cleared)", error: error)
                    SnackbarViewController.show(
                        "Failed to sign out: \(error.localizedDescription)",
                        duration: 4.0
                    )
                }
            }
        }
    }
}
