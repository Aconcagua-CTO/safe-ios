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
    private static let vaultListTitle = NSLocalizedString("ui_settings_vaults_title", comment: "Settings list title for vaults")

    private let tableBackgroundColor: UIColor = .backgroundPrimary
    private let sectionHeaderHeight: CGFloat = 28
    private var sections = [SectionItems]()

    private typealias SectionItems = (section: Section, items: [SectionItem])
    
    private var exportFlow: ExportDataFlow!
    private var importFlow: ImportDataFlow!
    private var deleteAccountService: UsersService?

    enum Section {
        case app(String)
        case support(String)
        case advanced(String)
        case about(String)

        enum App: SectionItem {
            case vaultList(String)
            case walletConnect(String)
            case ownerKeys(String, Bool, String)
            case addressBook(String)
            case passcode(String)
            case fiat(String, String)
            case chainPrefix(String)
            case appearance(String)
            case experimental(String)
            case herencia(String)
            case planes(String)
            case logout(String)
            case logoutAndReset(String)
            case deleteAccount(String)
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
        let appSectionTitle = NSLocalizedString("ui_settings_app_section_title", comment: "Settings section title for main app settings")
        var appSection: (section: AppSettingsViewController.Section, items: [SectionItem]) = (section: .app(appSectionTitle), items: [])
        
        appSection.items.append(contentsOf: [
            Section.App.vaultList(Self.vaultListTitle),
            Section.App.ownerKeys(NSLocalizedString("ui_settings_keys_title", comment: "Settings list title for keys"),
                                  !KeyInfo.keysWithoutBackup().isEmpty,
                                  "\(KeyInfo.count())"),
            Section.App.passcode(NSLocalizedString("ui_settings_security_title", comment: "Settings list title for security")),
            Section.App.addressBook(NSLocalizedString("ui_settings_address_book_title", comment: "Settings list title for address book")),
            Section.App.herencia(NSLocalizedString("ui_settings_inheritance_title", comment: "Settings list title for inheritance"))
        ])

        if App.configuration.services.environment.isDevelopment {
            appSection.items.append(Section.App.planes(NSLocalizedString("ui_settings_plans_title", comment: "Settings list title for plans")))
        }

        appSection.items.append(Section.Support.chatWithUs(NSLocalizedString("ui_settings_help_title", comment: "Settings list title for help")))
        
        // Show these settings in Development environment only (Debug + Release)
        if App.configuration.services.environment.isDevelopment {
            appSection.items.append(contentsOf: [
                Section.App.fiat(NSLocalizedString("ui_settings_fiat_currency_title", comment: "Settings list title for fiat currency"),
                                 AppSettings.selectedFiatCode),
                Section.App.chainPrefix(NSLocalizedString("ui_settings_chain_prefix_title", comment: "Settings list title for chain prefix")),
                Section.App.appearance(NSLocalizedString("ui_settings_appearance_title", comment: "Settings list title for appearance"))
            ])
        }
        
        // Add logout option if user is authenticated
        if App.shared.authRepository.isAuthenticated() {
            appSection.items.append(Section.App.logout(NSLocalizedString("ui_settings_sign_out_title", comment: "Settings list title for sign out")))
            if App.configuration.services.environment.isDevelopment {
                appSection.items.append(Section.App.logoutAndReset(NSLocalizedString("ui_settings_sign_out_reset_title", comment: "Settings list title for sign out and reset")))
            }
            appSection.items.append(Section.App.deleteAccount(NSLocalizedString("ui_settings_delete_account_title", comment: "Settings list title for delete account")))
        }
        
        let supportSection: (section: AppSettingsViewController.Section, items: [SectionItem]) = (section: .support(NSLocalizedString("ui_settings_support_feedback_title", comment: "Settings section title for support & feedback")), items: [])
        var advancedSection: (section: AppSettingsViewController.Section, items: [SectionItem]) = (section: .advanced(NSLocalizedString("ui_settings_advanced_title", comment: "Settings section title for advanced")), items: [
            Section.Advanced.advanced(NSLocalizedString("ui_settings_advanced_title", comment: "Settings item title for advanced")),
            Section.Advanced.dataExport(NSLocalizedString("ui_settings_export_data_title", comment: "Settings item title for export data")),
            Section.Advanced.dataImport(NSLocalizedString("ui_settings_import_data_title", comment: "Settings item title for import data"))
        ])
        
        if App.configuration.services.environment.isDevelopment {
            advancedSection.items.append(
                Section.Advanced.toggles(NSLocalizedString("ui_settings_feature_toggles_title", comment: "Settings item title for feature toggles"))
            )
        }

        let aboutSectionTitle = NSLocalizedString("ui_settings_about_title", comment: "Settings section title for about")
        let aboutSafeTitle = NSLocalizedString("ui_settings_about_safe_title", comment: "Settings item title for about Safe Wallet")
        let appVersionTitle = NSLocalizedString("ui_settings_app_version_title", comment: "Settings item title for app version")
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
                             .IntercomUnreadConversationCountDidChange] {
            notificationCenter.addObserver(
                self,
                selector: #selector(reload),
                name: notification,
                object: nil)
        }
    }

    private func showDappsViewController() {
        let dappsVC = DappsViewController(namedClass: nil)
        show(dappsVC, sender: self)
    }

    private func showOwnerKeys() {
        let vc = OwnerKeysListViewController()
        show(vc, sender: self)
    }

    private func presentVaultList() {
        let nav = UINavigationController(rootViewController: GroupedSwitchSafesViewController())
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

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = sections[indexPath.section].items[indexPath.row]
        switch item {

        case Section.App.vaultList(let name):
            return tableView.basicCell(name: name, icon: "tab-icon-balances", iconTintColor: .icon, indexPath: indexPath)
            
        case Section.App.walletConnect(let name):
            return tableView.basicCell(
                name: name,
                icon: "tab-icon-dapps",
                iconTintColor: .icon,
                indexPath: indexPath)
            
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
            
        case Section.App.planes(let name):
            return tableView.basicCell(name: name, icon: "ico-app-settings-desktop-pairing", indexPath: indexPath)
            
        case Section.App.logout(let name):
            let cell = tableView.basicCell(name: name, icon: "ico-app-settings-lock", indexPath: indexPath)
            if let userIdentity = currentUserIdentityString() {
                let titleAttributes = GNOTextStyle.headline.attributes
                let subtitleAttributes = GNOTextStyle.footnoteSecondary.attributes
                let attributed = NSMutableAttributedString(string: name, attributes: titleAttributes)
                attributed.append(NSAttributedString(string: "\n" + userIdentity, attributes: subtitleAttributes))
                cell.titleLabel.attributedText = attributed
                cell.titleLabel.numberOfLines = 0
            }
            return cell

        case Section.App.logoutAndReset(let name):
            return tableView.basicCell(name: name, icon: "ico-app-settings-lock", indexPath: indexPath)

        case Section.App.deleteAccount(let name):
            let cell = tableView.basicCell(name: name, icon: "ico-app-settings-lock", indexPath: indexPath)
            cell.titleLabel.textColor = .error
            return cell

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

        case Section.App.walletConnect:
            showDappsViewController()

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
            
        case Section.App.planes:
            let comingSoonVC = ComingSoonViewController()
            show(comingSoonVC, sender: self)
            
        case Section.App.logout:
            handleLogout()

        case Section.App.logoutAndReset:
            handleLogoutAndReset()

        case Section.App.deleteAccount:
            handleDeleteAccount()

        case Section.Support.chatWithUs:
            Tracker.trackEvent(.userOpenIntercom)
            openWhatsAppSupportChat()
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

    private func openWhatsAppSupportChat() {
        PublicConfigService.shared.getWhatsAppSupportConfig { phoneNumber, message in
            let encodedMessage = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? message
            guard let url = URL(string: "https://wa.me/\(phoneNumber)?text=\(encodedMessage)") else { return }
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let section = sections[section].section
        let view = tableView.dequeueHeaderFooterView(BasicHeaderView.self)
        switch section {
        case Section.app(let name):
            view.setName(name)

        case Section.support(let name):
            view.setName(name)
            
        case Section.advanced(let name):
            view.setName(name)
            
        case Section.about(let name):
            view.setName(name)
        }
        
        return view
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let item = sections[indexPath.section].items[indexPath.row]
        if case Section.App.logout = item, currentUserIdentityString() != nil {
            return 76
        }
        return BasicCell.rowHeight
    }
  
    override func tableView(_ tableView: UITableView, heightForHeaderInSection _section: Int) -> CGFloat {
        let section = sections[_section].section
        switch section {
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
        return false
    }

    func navigate(to route: NavigationRoute) {
        if route.path == NavigationRoute.appearanceSettings().path {
            navigateToAppearance()
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
    
    private func currentUserFirstName() -> String? {
        guard let displayName = App.shared.authRepository.getCurrentUser()?.displayName else {
            return nil
        }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
    }

    private func currentUserIdentityString() -> String? {
        let firstName = currentUserFirstName()
        let email = App.shared.authRepository.getCurrentUser()?.email
        guard firstName != nil || email != nil else { return nil }
        if let firstName = firstName, let email = email {
            return "\(firstName) - \(email)"
        }
        return firstName ?? email
    }

    private func handleLogout() {
        AuthLogger.info("User initiated logout from settings")
        
        // Show confirmation alert
        let alert = UIAlertController(
            title: "Sign Out",
            message: "Are you sure you want to sign out?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("cancel", comment: "Cancel action title"), style: .cancel))
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

        alert.addAction(UIAlertAction(title: NSLocalizedString("cancel", comment: "Cancel action title"), style: .cancel))
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

    // MARK: - Delete Account

    private func handleDeleteAccount() {
        AuthLogger.info("User initiated account deletion from settings")

        let alert = UIAlertController(
            title: NSLocalizedString("ui_delete_account_title", comment: "Delete account alert title"),
            message: NSLocalizedString("ui_delete_account_message", comment: "Delete account alert message"),
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: NSLocalizedString("cancel", comment: "Cancel action title"), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("ui_delete_account_confirm", comment: "Delete account confirm button"), style: .destructive) { [weak self] _ in
            self?.performDeleteAccount()
        })

        present(alert, animated: true)
    }

    private func performDeleteAccount() {
        guard let uid = App.shared.authRepository.getCurrentUser()?.uid else {
            AuthLogger.error("Cannot delete account: no authenticated user")
            return
        }

        AuthLogger.info("Performing account deletion for user: \(uid)")

        // Retain the service until the async call completes.
        let service = UsersService(authRepository: App.shared.authRepository)
        self.deleteAccountService = service

        service.deleteUser(userId: uid) { [weak self] result in
            guard let self = self else { return }
            self.deleteAccountService = nil

            DispatchQueue.main.async {
                switch result {
                case .success:
                    AuthLogger.success("Backend account deletion successful, cleaning up local state")

                    App.shared.authRepository.signOut { [weak self] _ in
                        guard let self = self else { return }
                        DispatchQueue.main.async {
                            // Reset user-session state tied to the deleted account.
                            AppSettings.termsAccepted = false
                            AppSettings.onboardingCompleted = false
                            AppSettings.companyId = nil
                            AppSettings.enterpriseRolsData = nil
                            AppSettings.leadCardManufacturer = nil
                            AppSettings.isNewSignUp = false
                            AppSettings.pendingOwnerKeysRegistration = false
                            AppSettings.importedOwnerKey = false
                            AppSettings.pendingPostSignupInstructions = false
                            AppSettings.didShowPostSignupInstructions = false
                            AppSettings.activeVaultGroupAddress = nil

                            // Remove all local vaults and owner keys before routing out.
                            try? Safe.removeAll()
                            try? OwnerKeyController.deleteAllKeys(showingMessage: false)

                            if let sceneDelegate = self.view.window?.windowScene?.delegate as? SceneDelegate {
                                sceneDelegate.onAppUpdateCompletion()
                            }
                        }
                    }

                case .failure(let error):
                    AuthLogger.error("Account deletion failed", error: error)
                    SnackbarViewController.show(
                        "Failed to delete account: \(error.localizedDescription)",
                        duration: 4.0
                    )
                }
            }
        }
    }
}
