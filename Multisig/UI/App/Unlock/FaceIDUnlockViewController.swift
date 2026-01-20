//
//  FaceIDUnlockViewController.swift
//  Multisig
//
//  Created by Vitaly on 31.01.23.
//  Copyright © 2023 Gnosis Ltd. All rights reserved.
//

import UIKit

class FaceIDUnlockViewController: UIViewController {

    @IBOutlet private weak var label: UILabel!

    @IBOutlet private weak var unlockButton: UIButton!

    var completion: (_ success: Bool, _ reset: Bool) -> Void = { _, _ in }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.isNavigationBarHidden = true
        label.setStyle(.slogan)
        unlockButton.setText("Unlock", .filled)
        unlockDataStore()
    }

    fileprivate func unlockDataStore() {
        #if DEBUG
        LogService.shared.debug("[FaceIDUnlock] Attempting to unlock data store")
        LogService.shared.debug("[FaceIDUnlock] Lock method: \(App.shared.securityCenter.lockMethod.rawValue)")
        #endif
        
        do {
            try App.shared.securityCenter.unlockDataStore()
            #if DEBUG
            LogService.shared.debug("[FaceIDUnlock] Successfully unlocked with biometry")
            #endif
            self.completion(true, false)
        } catch let error as GSError.CancelledByUser {
            // User cancelled - if lock method requires passcode, fall back to passcode entry
            #if DEBUG
            LogService.shared.debug("[FaceIDUnlock] User cancelled biometry")
            #endif
            if App.shared.securityCenter.lockMethod.isPasscodeRequired() {
                // Fall back to passcode entry
                #if DEBUG
                LogService.shared.debug("[FaceIDUnlock] Falling back to passcode entry")
                #endif
                self.completion(false, false)
            } else {
                // Biometry-only mode - just cancel
                #if DEBUG
                LogService.shared.debug("[FaceIDUnlock] Biometry-only mode, staying on Face ID screen")
                #endif
                self.completion(false, false)
            }
        } catch {
            // Other errors - if lock method requires passcode, fall back to passcode entry
            #if DEBUG
            LogService.shared.debug("[FaceIDUnlock] Biometry failed with error: \(error.localizedDescription)")
            #endif
            if App.shared.securityCenter.lockMethod.isPasscodeRequired() {
                // Fall back to passcode entry
                #if DEBUG
                LogService.shared.debug("[FaceIDUnlock] Falling back to passcode entry")
                #endif
                self.completion(false, false)
            } else {
                // Log error but don't show passcode entry for biometry-only mode
                LogService.shared.error("Failed to unlock with biometry", error: error)
                #if DEBUG
                LogService.shared.debug("[FaceIDUnlock] Biometry-only mode, staying on Face ID screen")
                #endif
                self.completion(false, false)
            }
        }
    }

    @IBAction func didTapUnlock(_ sender: Any) {
        unlockDataStore()
    }
}
