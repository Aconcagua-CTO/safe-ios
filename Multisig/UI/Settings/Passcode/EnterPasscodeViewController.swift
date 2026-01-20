//
//  EnterPasscodeViewController.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 14.04.22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import Foundation
import UIKit

class EnterPasscodeViewController: PasscodeViewController {
    enum SecurityCenterBehavior {
        /// Default behavior: only validates the passcode and returns it via completion.
        case validateOnly
        /// Used for the global app unlock flow: unlocks the SecurityCenter data store before returning.
        /// This avoids running PBKDF2 + keychain work twice (validate + unlock) on the main thread.
        case unlockDataStoreForAppUnlock
    }

    enum Result {
        //TODO: Remove optional when remove the old security code
        case success(String?)
        case close
    }

    var passcodeCompletion: (_ result: Result) -> Void = { _ in }

    var navigationItemTitle = "Enter Passcode"
    var screenTrackingEvent = TrackingEvent.enterPasscode
    var showsCloseButton: Bool = true
    var usesBiometry: Bool = true
    var warnAfterWrongAttemptCount: Int = 5
    var wrongAttemptsCount: Int = 0
    var securityCenterBehavior: SecurityCenterBehavior = .validateOnly

    private var isProcessing = false

    convenience init() {
        self.init(namedClass: PasscodeViewController.self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = navigationItemTitle
        promptLabel.text = "Enter your current passcode"
        button.setText("Forgot your passcode?", .plain)
        detailLabel.isHidden = true

        if showsCloseButton {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .close,
                target: self,
                action: #selector(didTapCloseButton))
        }

        biometryButton.isHidden = !canUseBiometry
        biometryButton.setImage(App.shared.auth.isFaceID ? UIImage(named: "ic-face-id") : UIImage(named: "ic-touch-id"), for: .normal)
    }

    private var canUseBiometry: Bool {
        guard usesBiometry && App.shared.auth.isBiometryAuthenticationPossible else {
            #if DEBUG
            LogService.shared.debug("[EnterPasscode] canUseBiometry = false (usesBiometry: \(usesBiometry), authPossible: \(App.shared.auth.isBiometryAuthenticationPossible))")
            #endif
            return false
        }
        
        let result: Bool
        if AppConfiguration.FeatureToggles.securityCenter {
            // For SecurityCenter: check if lock method requires user presence
            result = App.shared.securityCenter.lockMethod.isUserPresenceRequired()
            #if DEBUG
            LogService.shared.debug("[EnterPasscode] canUseBiometry (SecurityCenter) = \(result) (lockMethod: \(App.shared.securityCenter.lockMethod.rawValue))")
            #endif
        } else {
            // Legacy system: check passcode options
            result = AppSettings.passcodeOptions.contains(.useBiometry)
            #if DEBUG
            LogService.shared.debug("[EnterPasscode] canUseBiometry (legacy) = \(result) (passcodeOptions: \(AppSettings.passcodeOptions.rawValue))")
            #endif
        }
        
        return result
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Tracker.trackEvent(screenTrackingEvent)
        authenticateWithBiometry()
    }

    fileprivate func didEnterEnoughSymbols(_ text: String) {
        guard !isProcessing else { return }
        isProcessing = true

        // Prevent additional input while we validate/unlock.
        textField.isEnabled = false
        symbolsButton.isEnabled = false
        biometryButton.isEnabled = false

        let startedAt = CFAbsoluteTimeGetCurrent()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            if AppConfiguration.FeatureToggles.securityCenter {
                // PBKDF2 is expensive; derive off the main thread.
                let derived = App.shared.securityCenter.derivedKey(from: text)

                switch self.securityCenterBehavior {
                case .validateOnly:
                    let isCorrect = App.shared.securityCenter.isDataStorePasscodeCorrect(derivedPassword: derived)
                    DispatchQueue.main.async {
                        self.finishProcessing(startedAt: startedAt, success: isCorrect, passcode: text)
                    }
                case .unlockDataStoreForAppUnlock:
                    DispatchQueue.main.async {
                        do {
                            try App.shared.securityCenter.unlockDataStore(derivedPassword: derived)
                            self.finishProcessing(startedAt: startedAt, success: true, passcode: nil)
                        } catch {
                            // Wrong passcode (or other keychain failure) -> allow retry.
                            self.finishProcessing(startedAt: startedAt, success: false, passcode: nil)
                        }
                    }
                }
            } else {
                // Legacy passcode system (App.shared.auth)
                let isCorrect: Bool
                do {
                    isCorrect = try App.shared.auth.isPasscodeCorrect(plaintextPasscode: text)
                } catch {
                    DispatchQueue.main.async {
                        self.finishProcessing(startedAt: startedAt, success: false, passcode: nil)
                    }
                    return
                }
                DispatchQueue.main.async {
                    self.finishProcessing(startedAt: startedAt, success: isCorrect, passcode: text)
                }
            }
        }
    }

    override func willChangeText(_ text: String) {
        super.willChangeText(text)
        errorLabel.isHidden = true
        if text.count == passcodeLength {
            didEnterEnoughSymbols(text)
        }
    }

    @objc func didTapCloseButton() {
        self.passcodeCompletion(.close)
    }

    override func didTapButton(_ sender: Any) {
        let alertController = UIAlertController(
            title: "Remove all content",
            message: "Disabling the passcode will remove all app content. This cannot be undone. Please type in \"Remove\" to continue.",
            preferredStyle: .alert)

        alertController.addTextField()

        let remove = UIAlertAction(title: "Disable Passcode", style: .destructive) { [unowned self] _ in
            guard alertController.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) == "Remove" else {
                return
            }
            do {
                self.passcodeCompletion(.close)
                try App.shared.auth.deleteAllData()
            } catch {
                showGenericError(description: "Failed to remove passcode", error: error)
                return
            }
        }
        let cancel = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        alertController.addAction(remove)
        alertController.addAction(cancel)
        
        if let popoverPresentationController = alertController.popoverPresentationController {
            popoverPresentationController.sourceView = button
        }
        
        present(alertController, animated: true)
    }

    override func didTapBiometry(_ sender: Any) {
        authenticateWithBiometry()
    }

    private func authenticateWithBiometry() {
        guard canUseBiometry else { return }

        App.shared.auth.authenticateWithBiometrics { [weak self] result in
            guard let `self` = self else { return }
            switch result {
            case .success:
                // Most SecurityCenter biometry-based unlock is handled by FaceIDUnlockViewController.
                // Still, if we ended up here in the global unlock flow, make sure we actually
                // unlock the data store before proceeding (fallback safety).
                if AppConfiguration.FeatureToggles.securityCenter,
                   self.securityCenterBehavior == .unlockDataStoreForAppUnlock {
                    do {
                        try App.shared.securityCenter.unlockDataStore(userPassword: nil)
                        self.passcodeCompletion(.success(nil))
                    } catch {
                        self.showIncorrectPasscodeError()
                    }
                } else {
                    self.passcodeCompletion(.success(nil))
                }
            case .failure(_):
                self.biometryButton.isHidden = !self.canUseBiometry
            }
        }
    }

    private func finishProcessing(startedAt: CFAbsoluteTime, success: Bool, passcode: String?) {
        let dtMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
        LogService.shared.info("[EnterPasscode] processed in \(dtMs)ms success=\(success) securityCenter=\(AppConfiguration.FeatureToggles.securityCenter)")

        isProcessing = false
        textField.isEnabled = true
        symbolsButton.isEnabled = true
        biometryButton.isEnabled = true

        if success {
            passcodeCompletion(.success(passcode))
        } else {
            wrongAttemptsCount += 1
            if wrongAttemptsCount >= warnAfterWrongAttemptCount {
                showError("\(wrongAttemptsCount) failed password attempts. You can reset password via \"Forgot passcode?\" button below.")
            } else {
                showError("Wrong passcode")
            }
        }
    }
}

