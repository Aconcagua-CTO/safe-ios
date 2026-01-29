//
//  PostLoginGateEvaluatorTests.swift
//  MultisigTests
//
//  Created by Cursor on 2026-01-21.
//

import XCTest
@testable import Multisig

final class PostLoginGateEvaluatorTests: XCTestCase {
    func test_startMobileKeyWhenMissingEvenIfNotSynced() {
        let state = PostLoginGateState(
            hasSyncedVaults: false,
            hasVaults: false,
            hasMobileKey: false,
            hasCardKey: false
        )

        XCTAssertEqual(PostLoginGateEvaluator.nextAction(for: state), .startMobileKeyFlow)
    }

    func test_syncVaultsWhenKeysPresent() {
        let state = PostLoginGateState(
            hasSyncedVaults: false,
            hasVaults: false,
            hasMobileKey: true,
            hasCardKey: true
        )

        XCTAssertEqual(PostLoginGateEvaluator.nextAction(for: state), .syncVaults)
    }

    func test_showPendingVaultActivationWhenNoVaultsAfterSync() {
        let state = PostLoginGateState(
            hasSyncedVaults: true,
            hasVaults: false,
            hasMobileKey: true,
            hasCardKey: true
        )

        XCTAssertEqual(PostLoginGateEvaluator.nextAction(for: state), .showPendingVaultActivation)
    }

    func test_showMainWhenEverythingReady() {
        let state = PostLoginGateState(
            hasSyncedVaults: true,
            hasVaults: true,
            hasMobileKey: true,
            hasCardKey: true
        )

        XCTAssertEqual(PostLoginGateEvaluator.nextAction(for: state), .showMain)
    }
}
