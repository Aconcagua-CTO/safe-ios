//
//  UIViewController+Display.swift
//  Multisig
//
//  Created by Mouaz on 9/29/22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import UIKit
extension UIViewController {
    var isDarkMode: Bool {
        let forcedMode = App.shared.theme.displayMode
        if forcedMode != .unspecified {
            return forcedMode == .light
        }
        return traitCollection.userInterfaceStyle == .light
    }
}
