//
//  CrashlyticsConfigurator.swift
//  Multisig
//
//  Centralizes Crashlytics setup (metadata + user identity) once Firebase is configured.
//

import Foundation
import Firebase
import FirebaseAuth
import FirebaseCrashlytics

enum CrashlyticsConfigurator {
    /// Call after `FirebaseApp.configure()` and after tracking state is applied.
    static func configureIfPossible() {
        guard FirebaseApp.app() != nil else { return }

        let crashlytics = Crashlytics.crashlytics()

        // Environment / build metadata (high-signal, no PII)
        crashlytics.setCustomValue(App.configuration.services.environment.rawValue, forKey: "service_env")
        crashlytics.setCustomValue(App.configuration.app.bundleIdentifier, forKey: "bundle_id")
        crashlytics.setCustomValue(App.configuration.app.marketingVersion, forKey: "app_version")
        crashlytics.setCustomValue(App.configuration.app.buildVersion, forKey: "build_number")
        crashlytics.setCustomValue(AppSettings.termsAccepted, forKey: "terms_accepted")
        crashlytics.setCustomValue(AppSettings.trackingEnabled, forKey: "tracking_enabled")

        // User identity (only when tracking is enabled)
        updateUserIdentity(trackingEnabled: AppSettings.trackingEnabled)
    }

    static func updateUserIdentity(trackingEnabled: Bool) {
        guard FirebaseApp.app() != nil else { return }

        let crashlytics = Crashlytics.crashlytics()

        guard trackingEnabled else {
            // Crashlytics doesn't provide a clear API; setting empty string effectively de-identifies.
            crashlytics.setUserID("")
            return
        }

        if let uid = Auth.auth().currentUser?.uid {
            crashlytics.setUserID(uid)
        }
    }
}

