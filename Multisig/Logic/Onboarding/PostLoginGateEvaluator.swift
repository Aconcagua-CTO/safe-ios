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
        if state.requiresCardKey && !state.hasCardKey {
            return .startCardKeyFlow
        }
        if !state.hasMobileKey {
            return .startMobileKeyFlow
        }
        if !state.hasSyncedVaults {
            return .syncVaults
        }
        if !state.hasVaults {
            return .showPendingVaultActivation
        }
        return .showMain
    }
}
