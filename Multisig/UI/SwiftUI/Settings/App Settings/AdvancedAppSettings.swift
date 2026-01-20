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
            
            // MARK: - Burner Card Options
            BurnerCardOptionsSection()

            // NOTE: disabling to debug crash reporting in production environment
            if !(App.configuration.services.environment == .production) ||
                FirebaseRemoteConfig.shared.value(key: .crashDebugEnabled) == "YES" {
                Section(header: SectionHeader("DEBUG")) {
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
                        Button("Close", role: .cancel) { }
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
    @State private var isConfiguringNDEF = false
    @State private var showError: String?
    @State private var showSuccess = false
    @State private var successMessage = ""
    
    var body: some View {
        Section(header: SectionHeader("BURNER CARD")) {
            Button(action: {
                BurnerLogger.info("📝 BURNER OPTIONS: User tapped Disable Burner URL (TXT NDEF) from Advanced Settings")
                setNdefUseTextRecord(true)
            }) {
                HStack {
                    Text("Disable Burner URL (TXT NDEF)").body()
                    if isConfiguringNDEF {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    }
                }
            }
            .disabled(isConfiguringNDEF)
            
            Button(action: {
                BurnerLogger.info("📝 BURNER OPTIONS: User tapped Enable Burner URL (URI NDEF) from Advanced Settings")
                setNdefUseTextRecord(false)
            }) {
                Text("Enable Burner URL (URI NDEF)").body()
            }
            .disabled(isConfiguringNDEF)
        }
        .alert("Success", isPresented: $showSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(successMessage)
        }
        .alert("Error", isPresented: .constant(showError != nil)) {
            Button("OK", role: .cancel) {
                showError = nil
            }
        } message: {
            if let error = showError {
                Text(error)
            }
        }
    }
    
    private func setNdefUseTextRecord(_ enabled: Bool) {
        guard !isConfiguringNDEF else { return }
        isConfiguringNDEF = true
        
        Task {
            do {
                try await BurnerService.shared.setBurnerNDEFUsesTextRecord(
                    enabled,
                    alertMessage: enabled
                        ? "Hold your Burner card near the top of your iPhone to disable URL handling (TXT NDEF)."
                        : "Hold your Burner card near the top of your iPhone to enable URL handling (URI NDEF)."
                )
                
                await MainActor.run {
                    isConfiguringNDEF = false
                    successMessage = enabled
                        ? "Done. This Burner card will now expose a TEXT NDEF record instead of a URL (URI) record."
                        : "Done. This Burner card will now expose a URL (URI) NDEF record instead of a TEXT record."
                    showSuccess = true
                    BurnerLogger.info("📝 BURNER OPTIONS: ✅ Burner NDEF flags updated successfully (flagUseText=\(enabled))")
                }
            } catch {
                await MainActor.run {
                    isConfiguringNDEF = false
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
