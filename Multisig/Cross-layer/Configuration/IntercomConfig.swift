//
// Created by Dirk Jäckel on 23.11.21.
// Copyright (c) 2021 Gnosis Ltd. All rights reserved.
//

import Foundation
import Intercom

class IntercomConfig {

    static var pushNotificationUserInfo: [AnyHashable : Any]?
    private static var didConfigureIntercom = false

    static func setUp() {
        guard let protected = App.configuration.protected else {
            LogService.shared.info("Intercom setup skipped: protected configuration not available")
            return
        }
        
        let apiKey = protected[.INTERCOM_API_KEY]
        let appId = protected[.INTERCOM_APP_ID]
        
        guard !apiKey.isEmpty && !appId.isEmpty else {
            LogService.shared.info("Intercom setup skipped: API credentials not configured")
            return
        }
        
        Intercom.setApiKey(apiKey, forAppId: appId)
        didConfigureIntercom = true

        #if DEBUG
        Intercom.enableLogging()
        #endif
        IntercomConfig.disableChatOverlay()
    }

    private static func disableChatOverlay() {
        Intercom.setInAppMessagesVisible(false)
    }

    static func startChat() {
        // Intercom crashes on some error paths if presented before a user session is registered.
        // Ensure we are configured and logged in before presenting.
        guard let protected = App.configuration.protected else {
            LogService.shared.info("Intercom startChat skipped: protected configuration not available")
            App.shared.snackbar.show(message: NSLocalizedString("ui_support_chat_not_available", comment: "Support chat not available"))
            return
        }

        let apiKey = protected[.INTERCOM_API_KEY]
        let appId = protected[.INTERCOM_APP_ID]

        guard !apiKey.isEmpty && !appId.isEmpty else {
            LogService.shared.info("Intercom startChat skipped: API credentials not configured")
            App.shared.snackbar.show(message: NSLocalizedString("ui_support_chat_not_configured", comment: "Support chat not configured"))
            return
        }

        if !didConfigureIntercom {
            Intercom.setApiKey(apiKey, forAppId: appId)
            didConfigureIntercom = true
            IntercomConfig.disableChatOverlay()
        }

        Intercom.loginUnidentifiedUser { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    LogService.shared.debug("Intercom loginUnidentifiedUser succeeded; presenting messenger")
                    Intercom.present()
                case .failure(let error):
                    LogService.shared.error(String(format: NSLocalizedString("ui_intercom_anonymous_login_failed_format", comment: "Intercom anonymous login failed"),
                                                     "\(error)"))
                    App.shared.snackbar.show(message: NSLocalizedString("ui_support_chat_unavailable", comment: "Support chat unavailable"))
                }
            }
        }
    }

    static func hide() {
        Intercom.hide()
    }

    static func appDidShowMainContent() {
        // adding delay hack to handle the case when this shows right after app start -  in that case we would see the
        // black window background behind the intercom window. We give the app time to initialize.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) {
            guard let userInfo = IntercomConfig.pushNotificationUserInfo else {
                return
            }
            IntercomConfig.pushNotificationUserInfo = nil
            Intercom.handlePushNotification(userInfo)
            IntercomConfig.startChat()
        }
    }

    static func unreadConversationCount() -> UInt {
        Intercom.unreadConversationCount()
    }
    
    static func isIntercomPushNotification(_ userInfo: [AnyHashable : Any]) -> Bool {
        Intercom.isIntercomPushNotification(userInfo)
    }

    static func setDeviceToken(_ deviceToken: Data, failure: ((Error?) -> Void)? = nil) {
        Intercom.setDeviceToken(deviceToken, failure: failure)
    }
}
