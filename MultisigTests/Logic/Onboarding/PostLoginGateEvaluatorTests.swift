//
//  PostLoginGateEvaluatorTests.swift
//  MultisigTests
//
//  Created by Cursor on 2026-01-21.
//

import XCTest
@testable import Multisig

final class PostLoginGateEvaluatorTests: XCTestCase {
    func test_showMainForSignInEvenWhenMobileKeyMissingAndNotSynced() {
        let state = PostLoginGateState(
            hasSyncedVaults: false,
            hasVaults: false,
            hasMobileKey: false,
            hasCardKey: false,
            requiresCardKey: false,
            isSignUp: false
        )

        XCTAssertEqual(PostLoginGateEvaluator.nextAction(for: state), .showMain)
    }

    func test_startMobileKeyForSignupWhenMissingAndNotSynced() {
        let state = PostLoginGateState(
            hasSyncedVaults: false,
            hasVaults: false,
            hasMobileKey: false,
            hasCardKey: false,
            requiresCardKey: false,
            isSignUp: true
        )

        XCTAssertEqual(PostLoginGateEvaluator.nextAction(for: state), .startMobileKeyFlow)
    }

    func test_showMainWhenNotSignupAndNotSynced() {
        let state = PostLoginGateState(
            hasSyncedVaults: false,
            hasVaults: false,
            hasMobileKey: true,
            hasCardKey: true,
            requiresCardKey: false,
            isSignUp: false
        )

        XCTAssertEqual(PostLoginGateEvaluator.nextAction(for: state), .showMain)
    }

    func test_showPendingVaultActivationWhenSignupAndNotSynced() {
        let state = PostLoginGateState(
            hasSyncedVaults: false,
            hasVaults: false,
            hasMobileKey: true,
            hasCardKey: true,
            requiresCardKey: false,
            isSignUp: true
        )

        XCTAssertEqual(PostLoginGateEvaluator.nextAction(for: state), .showPendingVaultActivation)
    }

    func test_showPendingVaultActivationWhenNoVaultsAfterSync() {
        let state = PostLoginGateState(
            hasSyncedVaults: true,
            hasVaults: false,
            hasMobileKey: true,
            hasCardKey: true,
            requiresCardKey: false,
            isSignUp: false
        )

        XCTAssertEqual(PostLoginGateEvaluator.nextAction(for: state), .showPendingVaultActivation)
    }

    func test_showMainWhenEverythingReady() {
        let state = PostLoginGateState(
            hasSyncedVaults: true,
            hasVaults: true,
            hasMobileKey: true,
            hasCardKey: true,
            requiresCardKey: false,
            isSignUp: false
        )

        XCTAssertEqual(PostLoginGateEvaluator.nextAction(for: state), .showMain)
    }
}
