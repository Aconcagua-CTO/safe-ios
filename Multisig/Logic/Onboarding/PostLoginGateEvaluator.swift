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
    let cardManufacturer: String
}

enum PostLoginGateAction {
    case startCardKeyFlow
    case syncVaults
    case showPendingVaultActivation
    case startMobileKeyFlow
    case showContactRequired
    case showMain
}

enum PostLoginGateEvaluator {
    private static let knownManufacturers: Set<String> = ["tangem", "burner", "mobile", "demo"]

    static func nextAction(for state: PostLoginGateState) -> PostLoginGateAction {
        #if DEBUG
        LogService.shared.debug(
            "[PostLoginGateEvaluator] state synced=\(state.hasSyncedVaults) vaults=\(state.hasVaults) " +
            "mobileKeys=\(state.mobileKeyCount)/\(state.requiredMobileKeyCount) cardKey=\(state.hasCardKey) " +
            "requiresCardKey=\(state.requiresCardKey) isSignUp=\(state.isSignUp) " +
            "cardManufacturer=\(state.cardManufacturer)"
        )
        #endif
        if !state.isSignUp {
            // Returning user: coordinator already verified they have registered keys.
            if !state.hasVaults {
                return .showPendingVaultActivation
            }
            return .showMain
        }
        if !knownManufacturers.contains(state.cardManufacturer) && !state.hasCardKey {
            return .showContactRequired
        }
        if state.requiresCardKey && !state.hasCardKey {
            return .startCardKeyFlow
        }
        if state.mobileKeyCount < state.requiredMobileKeyCount {
            return .startMobileKeyFlow
        }
        if !state.hasSyncedVaults {
            return .showPendingVaultActivation
        }
        if !state.hasVaults {
            return .showPendingVaultActivation
        }
        return .showMain
    }
}
