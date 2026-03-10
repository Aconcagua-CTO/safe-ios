//
//  AdvancedAppSettings.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 15.05.20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import SwiftUI
import UIKit
import Firebase
import FirebaseCrashlytics

struct AdvancedAppSettings: View {

    @ObservedObject
    var theme: Theme = App.shared.theme
    
    @State var showFCMToken = false
    @State var forceSpanishLanguage = AppSettings.debugForceSpanishLanguageEnabled
    
    var token: String {
        Multisig.App.shared.notificationHandler.token ?? ""
    }

    var body: some View {
        List {
            Section(header: SectionHeader("VAULTS")) {
                ToggleVaultSourceRow()
                ToggleMultiVaultBalancesRow()
            }

            Section(header: SectionHeader("TRANSACTIONS")) {
                ToggleSelfHostedExecuteRow()
            }
            
            Section(header: SectionHeader("TRACKING")) {
                ToggleTrackingRow()
            }

            DataSharingInfo()

            // MARK: - Tangem Card Options
            TangemCardOptionsSection()

            // MARK: - Tangem0 Backup Activation
            Tangem0BackupActivationSection()
            
            // MARK: - Burner Card Options
            BurnerCardOptionsSection()

            // NOTE: disabling to debug crash reporting in production environment
            if !(App.configuration.services.environment == .production) ||
                FirebaseRemoteConfig.shared.value(key: .crashDebugEnabled) == "YES" {
                Section(header: SectionHeader("DEBUG")) {
                    #if DEBUG
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $forceSpanishLanguage.didSet { enabled in
                            AppSettings.debugForceSpanishLanguageEnabled = enabled
                            AppSettings.applyDebugLanguageOverrideIfNeeded()
                        }) {
                            Text("Force Spanish (es-AR)").headline()
                        }
                        .frame(height: 60)
                        .toggleStyle(SwitchToggleStyle(tint: Color.success))

                        Text("May require app restart to fully apply.")
                            .body(.gray)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                    #endif

                    Button(action: {
                        let crashlytics = Crashlytics.crashlytics()
                        crashlytics.log("Advanced Settings: force Crashlytics crash triggered by user")
                        crashlytics.setCustomValue("advanced_settings", forKey: "force_crash_source")
                        crashlytics.setCustomValue(Date().description, forKey: "force_crash_timestamp")
                        fatalError("Crashlytics test crash triggered from Advanced Settings")
                    }) {
                        Text("Crash with Crashlytics").body()
                    }
                    
                    Button(action: {
                        fatalError()
                    }) {
                        Text("Crash the App").body()
                    }

                    Button(action: {
                        LogService.shared.error("Non-fatal triggerred", error: "Test non-fatal error (id \(Int.random(in: 0...10_000)))")
                    }) {
                        Text("Trigger non-fatal error").body()
                    }
                    
                    Button {
                        showFCMToken = true
                    } label: {
                        Text("Show FCM Token").body()
                    }
                    .alert("FCM Registration Token", isPresented: $showFCMToken) {
                        CopyButton(token) {
                            Text("Copy")
                        }
                        Button(NSLocalizedString("button_close", comment: "Close button title"), role: .cancel) { }
                    } message: {
                        Text(token)
                    }
                }
            }
        }
        .onAppear {
            Tracker.trackEvent(.settingsAppAdvanced)
        }
        .navigationBarTitle("Advanced", displayMode: .inline)
    }

    struct ToggleTrackingRow: View {
        @State
        private var trackingEnabled = AppSettings.trackingEnabled

        var body: some View {
            VStack {
                Toggle(isOn: $trackingEnabled.didSet { enabled in
                    AppSettings.trackingEnabled = enabled
                }) {
                    Text("Share Usage and Crash Data").headline()
                }
                .frame(height: 60)
                .toggleStyle(SwitchToggleStyle(tint: Color.success))
            }
        }
    }
    
    struct ToggleVaultSourceRow: View {
        @State
        private var useLocalVaults = AppSettings.useLocalVaults

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $useLocalVaults.didSet { enabled in
                    AppSettings.useLocalVaults = enabled
                }) {
                    Text("Use Local Vaults").headline()
                }
                .frame(height: 60)
                .toggleStyle(SwitchToggleStyle(tint: Color.success))
                
                Text("When enabled, the app will use locally stored vaults instead of syncing from the backend. Turn this off to enable backend vault synchronization (default).")
                    .body(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }
    
    struct ToggleMultiVaultBalancesRow: View {
        @State
        private var multiVaultEnabled = AppSettings.multiVaultBalancesEnabled
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $multiVaultEnabled.didSet { enabled in
                    #if DEBUG
                    LogService.shared.debug("[Multivault] Toggled multi-vault balances to \(enabled)")
                    #endif
                    AppSettings.multiVaultBalancesEnabled = enabled
                }) {
                    Text("Combine Balances from All Vaults").headline()
                }
                .frame(height: 60)
                .toggleStyle(SwitchToggleStyle(tint: Color.success))
                
                Text("When enabled, balances from all your vaults are grouped by token and shown together.")
                    .body(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }

    struct ToggleSelfHostedExecuteRow: View {
        @State
        private var selfHostedEnabled = AppSettings.selfHostedExecuteEnabled

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $selfHostedEnabled.didSet { enabled in
                    AppSettings.selfHostedExecuteEnabled = enabled
                }) {
                    Text("Self Hosted Execute").headline()
                }
                .frame(height: 60)
                .toggleStyle(SwitchToggleStyle(tint: Color.success))

                Text("When enabled, transaction execution is handled by Boveda backend instead of Safe gateway.")
                    .body(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }

    struct DataSharingInfo: View {
        var body: some View {
            VStack {
                Text("By sharing usage data, you are helping us improve the app with anonymized app usage data")
                    .body(.gray).frame(minHeight: 50)
                HStack {
                    BrowseLinkButton(title: "What data is shared?", url: App.configuration.legal.privacyURL)
                    Spacer()
                }
            }
            .padding()
            .background(Color.backgroundPrimary)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
    }
}

/// https://stackoverflow.com/questions/56996272/how-can-i-trigger-an-action-when-a-swiftui-toggle-is-toggled
fileprivate extension Binding {
    func didSet(execute: @escaping (Value) -> Void) -> Binding {
        return Binding(
            get: { self.wrappedValue },
            set: {
                self.wrappedValue = $0
                execute($0)
            }
        )
    }
}

// MARK: - Tangem0 Backup Activation Section

struct Tangem0BackupActivationSection: View {
    var body: some View {
        Section(header: SectionHeader("TANGEM0")) {
            Button(action: {
                TangemLogger.info("🟦 TANGEM0 OPTIONS: User tapped Activate Tangem0 (single)")
                presentTangem0SingleActivation()
            }) {
                Text("Activate Tangem0 (single)").body()
            }
            
            Button(action: {
                TangemLogger.info("🟦 TANGEM0 OPTIONS: User tapped Activate Tangem0 (Backup)")
                presentTangem0BackupActivation()
            }) {
                Text("Activate Tangem0 (Backup)").body()
            }
        }
    }

    private func presentTangem0SingleActivation() {
        DispatchQueue.main.async {
            guard let topViewController = self.topViewController() else {
                TangemLogger.error("🟦 TANGEM0 OPTIONS: ❌ Unable to locate active window for single activation")
                return
            }

            // A fixed, non-default access code is required to flip TAG_PinIsDefault to false on the
            // card firmware. With TAG_PinIsDefault=true the card enforces SmartSecurityDelay (15s)
            // on every signing session. Setting any non-default code eliminates the delay permanently.
            // Tangem0Service uses the same code when opening NFC sessions.
            let activationVC = TangemActivationViewController(accessCode: Tangem0Service.fixedAccessCode)
            let navVC = UINavigationController(rootViewController: activationVC)

            activationVC.onActivationComplete = { info in
                // Card is now activated with a non-default access code; import as Tangem0 key using SignRaw
                let flow = TangemKeyFlow(
                    activatedCardInfo: info,
                    service: Tangem0Service.shared,
                    keyType: .tangem0
                ) { _ in
                    navVC.dismiss(animated: true)
                }
                flow.skipIntro = true
                flow.push(from: activationVC)
            }

            topViewController.present(navVC, animated: true)
        }
    }

    private func presentTangem0BackupActivation() {
        DispatchQueue.main.async {
            guard let topViewController = self.topViewController() else {
                TangemLogger.error("🟦 TANGEM0 OPTIONS: ❌ Unable to locate active window for backup activation")
                return
            }

            let viewController = Tangem0BackupActivationViewController()
            let navController = UINavigationController(rootViewController: viewController)
            topViewController.present(navController, animated: true)
        }
    }

    private func topViewController() -> UIViewController? {
        let foregroundScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }

        if let top = foregroundScenes
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?
            .rootViewController {
            return findTopViewController(from: top)
        }

        let anySceneRoot = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first?.rootViewController }
            .first

        return anySceneRoot.flatMap { findTopViewController(from: $0) }
    }

    private func findTopViewController(from root: UIViewController) -> UIViewController? {
        if let presented = root.presentedViewController {
            return findTopViewController(from: presented)
        }
        if let nav = root as? UINavigationController {
            return nav.topViewController ?? nav
        }
        if let tab = root as? UITabBarController {
            return tab.selectedViewController
        }
        return root
    }
}

// MARK: - Tangem Card Options Section

struct TangemCardOptionsSection: View {
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        Section(header: SectionHeader("TANGEM CARD")) {
            Button(action: {
                TangemLogger.info("📖 TANGEM OPTIONS: User tapped Read Card from Advanced Settings")
                presentTangemCardReader()
            }) {
                Text("Read Card").body()
            }
            
            Button(action: {
                TangemLogger.info("🔧 TANGEM OPTIONS: User tapped Activate Card from Advanced Settings")
                presentTangemActivation()
            }) {
                Text("Activate Card").body()
            }
            
            Button(action: {
                TangemLogger.info("🔥 TANGEM OPTIONS: User tapped Factory Reset from Advanced Settings")
                presentTangemFactoryReset()
            }) {
                Text("Factory Reset").body()
                    .foregroundColor(.red)
            }
        }
    }
    
    private func presentTangemCardReader() {
        DispatchQueue.main.async {
            guard let topViewController = self.topViewController() else {
                TangemLogger.error("📖 TANGEM OPTIONS: ❌ Unable to locate active window to present card reader")
                return
            }
            
            let tangemVC = TangemCardReaderViewController()
            let navVC = UINavigationController(rootViewController: tangemVC)
            topViewController.present(navVC, animated: true)
        }
    }
    
    private func presentTangemActivation() {
        DispatchQueue.main.async {
            guard let topViewController = self.topViewController() else {
                TangemLogger.error("🔧 TANGEM OPTIONS: ❌ Unable to locate active window to present activation flow")
                return
            }
            
            let tangemVC = TangemActivationViewController()
            tangemVC.onActivationComplete = { info in
                importActivatedCardAsOwner(info)
            }
            let navVC = UINavigationController(rootViewController: tangemVC)
            topViewController.present(navVC, animated: true)
        }
    }
    
    private func presentTangemFactoryReset() {
        DispatchQueue.main.async {
            guard let topViewController = self.topViewController() else {
                TangemLogger.error("🔥 TANGEM OPTIONS: ❌ Unable to locate active window to present factory reset flow")
                return
            }
            
            let tangemVC = TangemFactoryResetViewController()
            let navVC = UINavigationController(rootViewController: tangemVC)
            topViewController.present(navVC, animated: true)
        }
    }
    
    private func topViewController() -> UIViewController? {
        let foregroundScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
        
        if let top = foregroundScenes
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?
            .rootViewController {
            return findTopViewController(from: top)
        }
        
        let anySceneRoot = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first?.rootViewController }
            .first
        
        return anySceneRoot.flatMap { findTopViewController(from: $0) }
    }
    
    private func findTopViewController(from root: UIViewController) -> UIViewController? {
        if let presented = root.presentedViewController {
            return findTopViewController(from: presented)
        }
        if let nav = root as? UINavigationController {
            return nav.topViewController ?? nav
        }
        if let tab = root as? UITabBarController {
            return tab.selectedViewController
        }
        return root
    }
    
    private func importActivatedCardAsOwner(_ info: ActivatedCardInfo) {
        let defaultName = "Tangem Card \(info.cardId.suffix(8))"
        
        // Directly import using OwnerKeyController
        let success = OwnerKeyController.importKey(
            tangemCardId: info.cardId,
            walletPublicKey: info.wallet.publicKey,
            address: info.ethereumAddress,
            name: defaultName,
            derivationPath: nil,
            walletIndex: info.wallet.index
        )
        
        if success {
            NotificationCenter.default.post(name: .ownerKeyImported, object: nil)
            TangemLogger.info("🔧 TANGEM OPTIONS: ✅ Owner imported successfully")
        } else {
            TangemLogger.error("🔧 TANGEM OPTIONS: ❌ Failed to import owner")
        }
    }
}

// MARK: - Burner Card Options Section

struct BurnerCardOptionsSection: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var isBusy = false
    @State private var showError: String?
    @State private var showSuccess = false
    @State private var successMessage = ""
    @State private var showCardInfo = false
    @State private var cardInfoText = ""
    @State private var showGenKeySlotPicker = false
    
    var body: some View {
        Section(header: SectionHeader(NSLocalizedString("ui_burner_card_section_header", comment: "Section header for Burner card advanced options"))) {
            Button(action: {
                BurnerLogger.info("📖 BURNER OPTIONS: User tapped Read Card from Advanced Settings")
                readCard()
            }) {
                HStack {
                    Text(NSLocalizedString("ui_burner_read_card", comment: "Read Burner card button")).body()
                    if isBusy {
                        Spacer()
                        ProgressView().progressViewStyle(CircularProgressViewStyle())
                    }
                }
            }
            .disabled(isBusy)
            
            Button(action: {
                BurnerLogger.info("🔑 BURNER OPTIONS: User tapped Generate Key from Advanced Settings")
                showGenKeySlotPicker = true
            }) {
                Text(NSLocalizedString("ui_burner_generate_key", comment: "Generate key on Burner card button")).body()
            }
            .disabled(isBusy)
            
            Button(action: {
                BurnerLogger.info("📝 BURNER OPTIONS: User tapped Disable Burner URL (TXT NDEF) from Advanced Settings")
                setNdefUseTextRecord(true)
            }) {
                Text(NSLocalizedString("ui_burner_disable_url_txt_ndef", comment: "Button to disable Burner URL handling by switching to TXT NDEF")).body()
            }
            .disabled(isBusy)
            
            Button(action: {
                BurnerLogger.info("📝 BURNER OPTIONS: User tapped Enable Burner URL (URI NDEF) from Advanced Settings")
                setNdefUseTextRecord(false)
            }) {
                Text(NSLocalizedString("ui_burner_enable_url_uri_ndef", comment: "Button to enable Burner URL handling by switching to URI NDEF")).body()
            }
            .disabled(isBusy)
        }
        .alert(NSLocalizedString("ui_success", comment: "Generic success title"), isPresented: $showSuccess) {
            Button(NSLocalizedString("ok", comment: "OK"), role: .cancel) { }
        } message: {
            Text(successMessage)
        }
        .alert(NSLocalizedString("ui_burner_card_info_title", comment: "Burner card info title"), isPresented: $showCardInfo) {
            Button(NSLocalizedString("ok", comment: "OK"), role: .cancel) { }
        } message: {
            Text(cardInfoText)
        }
        .alert(NSLocalizedString("ui_error", comment: "Generic error title"), isPresented: .constant(showError != nil)) {
            Button(NSLocalizedString("ok", comment: "OK"), role: .cancel) {
                showError = nil
            }
        } message: {
            if let error = showError {
                Text(error)
            }
        }
        .confirmationDialog(
            NSLocalizedString("ui_burner_generate_key_pick_slot", comment: "Pick a slot for key generation"),
            isPresented: $showGenKeySlotPicker,
            titleVisibility: .visible
        ) {
            Button("Slot 3") { generateKey(slot: 3) }
            Button("Slot 4") { generateKey(slot: 4) }
            Button("Slot 5") { generateKey(slot: 5) }
            Button(NSLocalizedString("button_close", comment: "Close button title"), role: .cancel) { }
        }
    }
    
    // MARK: - Read Card
    
    private func readCard() {
        guard !isBusy else { return }
        isBusy = true
        
        Task {
            do {
                let info = try await BurnerService.shared.readCardInfo()
                
                await MainActor.run {
                    isBusy = false
                    cardInfoText = formatCardInfo(info)
                    showCardInfo = true
                }
            } catch {
                await MainActor.run {
                    isBusy = false
                    showError = (error as? BurnerService.BurnerServiceError)?.errorDescription ?? error.localizedDescription
                    BurnerLogger.error("📖 BURNER OPTIONS: ❌ Failed to read card info", error: error)
                }
            }
        }
    }
    
    private func formatCardInfo(_ info: BurnerService.BurnerCardInfo) -> String {
        var lines: [String] = []
        lines.append("Card ID: \(info.cardId)")
        lines.append("Firmware: \(info.firmwareVersion ?? "unknown")")
        if let addon = info.addonVersion {
            lines.append("Addons: \(addon)")
        }
        lines.append("")
        for slot in info.slots {
            let status: String
            if slot.isInitialized {
                let addr = slot.ethereumAddress?.checksummed ?? "unknown"
                let pwd = slot.hasPassword ? " [pwd]" : ""
                status = "\(addr)\(pwd)"
            } else {
                status = "empty"
            }
            lines.append("Slot \(slot.slot): \(status)")
        }
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Generate Key
    
    private func generateKey(slot: Int) {
        guard !isBusy else { return }
        isBusy = true
        
        Task {
            do {
                let result = try await BurnerService.shared.generateKey(slot: slot)
                
                await MainActor.run {
                    isBusy = false
                    successMessage = String(
                        format: NSLocalizedString("ui_burner_key_generated_format", comment: "Key generated success message"),
                        slot, result.ethereumAddress.checksummed
                    )
                    showSuccess = true
                    BurnerLogger.info("🔑 BURNER OPTIONS: ✅ Key generated in slot \(slot), address=\(result.ethereumAddress.checksummed)")
                }
            } catch {
                await MainActor.run {
                    isBusy = false
                    showError = (error as? BurnerService.BurnerServiceError)?.errorDescription ?? error.localizedDescription
                    BurnerLogger.error("🔑 BURNER OPTIONS: ❌ Failed to generate key in slot \(slot)", error: error)
                }
            }
        }
    }
    
    // MARK: - NDEF Config
    
    private func setNdefUseTextRecord(_ enabled: Bool) {
        guard !isBusy else { return }
        isBusy = true
        
        Task {
            do {
                try await BurnerService.shared.setBurnerNDEFUsesTextRecord(
                    enabled,
                    alertMessage: enabled
                        ? NSLocalizedString("nfc_burner_hold_disable_url_txt_ndef", comment: "NFC prompt to disable Burner URL handling (TXT NDEF)")
                        : NSLocalizedString("nfc_burner_hold_enable_url_uri_ndef", comment: "NFC prompt to enable Burner URL handling (URI NDEF)")
                )
                
                await MainActor.run {
                    isBusy = false
                    successMessage = enabled
                        ? NSLocalizedString("ui_burner_done_txt_ndef", comment: "Success message after switching Burner to TXT NDEF")
                        : NSLocalizedString("ui_burner_done_uri_ndef", comment: "Success message after switching Burner to URI NDEF")
                    showSuccess = true
                    BurnerLogger.info("📝 BURNER OPTIONS: ✅ Burner NDEF flags updated successfully (flagUseText=\(enabled))")
                }
            } catch {
                await MainActor.run {
                    isBusy = false
                    let errorMessage = (error as? BurnerService.BurnerServiceError)?.errorDescription ?? error.localizedDescription
                    showError = errorMessage
                    BurnerLogger.error("📝 BURNER OPTIONS: ❌ Failed to update Burner NDEF flags", error: error)
                }
            }
        }
    }
}

struct AdvancedAppSettings_Previews: PreviewProvider {
    static var previews: some View {
        AdvancedAppSettings()
    }
}
