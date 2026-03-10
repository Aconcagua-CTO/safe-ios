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
    let mobileKeyCount: Int
    let requiredMobileKeyCount: Int
    let hasCardKey: Bool
    let requiresCardKey: Bool
    let isSignUp: Bool
    let hasRegisteredKeys: Bool
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
            "mobileKeys=\(state.mobileKeyCount)/\(state.requiredMobileKeyCount) cardKey=\(state.hasCardKey) " +
            "requiresCardKey=\(state.requiresCardKey) isSignUp=\(state.isSignUp) " +
            "hasRegisteredKeys=\(state.hasRegisteredKeys)"
        )
        #endif
        if !state.isSignUp && !state.hasSyncedVaults {
            let hasNoLocalKeys = state.mobileKeyCount == 0 && !state.hasCardKey
            if hasNoLocalKeys && !state.hasVaults && !state.hasRegisteredKeys {
                // Treat this returning login as first-time setup and continue to key flow checks.
            } else {
                return .showMain
            }
        }
        if state.requiresCardKey && !state.hasCardKey {
            return .startCardKeyFlow
        }
        if state.mobileKeyCount < state.requiredMobileKeyCount {
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
