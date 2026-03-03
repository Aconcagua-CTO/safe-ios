//
//  PostLoginGateEvaluator.swift
//  Multisig
//
//  Created by Cursor on 2026-01-21.
//

import Foundation

struct PostLoginGateState {
    let hasSyncedVaults: Bool
    let hasVaults: Bool
    let hasMobileKey: Bool
    let hasCardKey: Bool
    let requiresCardKey: Bool
    let isSignUp: Bool
}

enum PostLoginGateAction {
    case startCardKeyFlow
    case syncVaults
    case showPendingVaultActivation
    case startMobileKeyFlow
    case showMain
}

enum PostLoginGateEvaluator {
    static func nextAction(for state: PostLoginGateState) -> PostLoginGateAction {
        #if DEBUG
        LogService.shared.debug(
            "[PostLoginGateEvaluator] state synced=\(state.hasSyncedVaults) vaults=\(state.hasVaults) " +
            "mobileKey=\(state.hasMobileKey) cardKey=\(state.hasCardKey) " +
            "requiresCardKey=\(state.requiresCardKey) isSignUp=\(state.isSignUp)"
        )
        #endif
        // For non-sign-up logins we skip post-login key/vault sync gates and hand off
        // to Assets tab, where vault sync is shown with the custom loader.
        if !state.isSignUp && !state.hasSyncedVaults {
            return .showMain
        }
        if state.requiresCardKey && !state.hasCardKey {
            return .startCardKeyFlow
        }
        if !state.hasMobileKey {
            return .startMobileKeyFlow
        }
        if !state.hasSyncedVaults {
            return state.isSignUp ? .showPendingVaultActivation : .showMain
        }
        if !state.hasVaults {
            return .showPendingVaultActivation
        }
        return .showMain
    }
}
