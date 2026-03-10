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
            mobileKeyCount: 0,
            requiredMobileKeyCount: 1,
            hasCardKey: false,
            requiresCardKey: false,
            isSignUp: false,
            hasRegisteredKeys: true
        )

        XCTAssertEqual(PostLoginGateEvaluator.nextAction(for: state), .showMain)
    }

    func test_startMobileKeyForSignupWhenMissingAndNotSynced() {
        let state = PostLoginGateState(
            hasSyncedVaults: false,
            hasVaults: false,
            mobileKeyCount: 0,
            requiredMobileKeyCount: 1,
            hasCardKey: false,
            requiresCardKey: false,
            isSignUp: true,
            hasRegisteredKeys: true
        )

        XCTAssertEqual(PostLoginGateEvaluator.nextAction(for: state), .startMobileKeyFlow)
    }

    func test_showMainWhenNotSignupAndNotSynced() {
        let state = PostLoginGateState(
            hasSyncedVaults: false,
            hasVaults: false,
            mobileKeyCount: 1,
            requiredMobileKeyCount: 1,
            hasCardKey: true,
            requiresCardKey: false,
            isSignUp: false,
            hasRegisteredKeys: true
        )

        XCTAssertEqual(PostLoginGateEvaluator.nextAction(for: state), .showMain)
    }

    func test_showPendingVaultActivationWhenSignupAndNotSynced() {
        let state = PostLoginGateState(
            hasSyncedVaults: false,
            hasVaults: false,
            mobileKeyCount: 1,
            requiredMobileKeyCount: 1,
            hasCardKey: true,
            requiresCardKey: false,
            isSignUp: true,
            hasRegisteredKeys: true
        )

        XCTAssertEqual(PostLoginGateEvaluator.nextAction(for: state), .showPendingVaultActivation)
    }

    func test_showPendingVaultActivationWhenNoVaultsAfterSync() {
        let state = PostLoginGateState(
            hasSyncedVaults: true,
            hasVaults: false,
            mobileKeyCount: 1,
            requiredMobileKeyCount: 1,
            hasCardKey: true,
            requiresCardKey: false,
            isSignUp: false,
            hasRegisteredKeys: true
        )

        XCTAssertEqual(PostLoginGateEvaluator.nextAction(for: state), .showPendingVaultActivation)
    }

    func test_showMainWhenEverythingReady() {
        let state = PostLoginGateState(
            hasSyncedVaults: true,
            hasVaults: true,
            mobileKeyCount: 1,
            requiredMobileKeyCount: 1,
            hasCardKey: true,
            requiresCardKey: false,
            isSignUp: false,
            hasRegisteredKeys: true
        )

        XCTAssertEqual(PostLoginGateEvaluator.nextAction(for: state), .showMain)
    }

    func test_startMobileKeyFlowWhenMobileManufacturerNeedsSecondKey() {
        let state = PostLoginGateState(
            hasSyncedVaults: false,
            hasVaults: false,
            mobileKeyCount: 1,
            requiredMobileKeyCount: 2,
            hasCardKey: false,
            requiresCardKey: false,
            isSignUp: true,
            hasRegisteredKeys: true
        )

        XCTAssertEqual(PostLoginGateEvaluator.nextAction(for: state), .startMobileKeyFlow)
    }

    func test_proceedAfterSecondMobileKeyForMobileManufacturer() {
        let state = PostLoginGateState(
            hasSyncedVaults: false,
            hasVaults: false,
            mobileKeyCount: 2,
            requiredMobileKeyCount: 2,
            hasCardKey: false,
            requiresCardKey: false,
            isSignUp: true,
            hasRegisteredKeys: true
        )

        XCTAssertEqual(PostLoginGateEvaluator.nextAction(for: state), .showPendingVaultActivation)
    }

    func test_startCardKeyFlowForReturningLoginWithoutAnyKeysOrVaults() {
        let state = PostLoginGateState(
            hasSyncedVaults: false,
            hasVaults: false,
            mobileKeyCount: 0,
            requiredMobileKeyCount: 1,
            hasCardKey: false,
            requiresCardKey: true,
            isSignUp: false,
            hasRegisteredKeys: false
        )

        XCTAssertEqual(PostLoginGateEvaluator.nextAction(for: state), .startCardKeyFlow)
    }

    func test_startMobileKeyFlowForReturningLoginWithoutAnyKeysOrVaultsWhenCardNotRequired() {
        let state = PostLoginGateState(
            hasSyncedVaults: false,
            hasVaults: false,
            mobileKeyCount: 0,
            requiredMobileKeyCount: 1,
            hasCardKey: false,
            requiresCardKey: false,
            isSignUp: false,
            hasRegisteredKeys: false
        )

        XCTAssertEqual(PostLoginGateEvaluator.nextAction(for: state), .startMobileKeyFlow)
    }

    func test_showMainForReturningLoginWithoutLocalKeysWhenBackendKeysExist() {
        let state = PostLoginGateState(
            hasSyncedVaults: false,
            hasVaults: false,
            mobileKeyCount: 0,
            requiredMobileKeyCount: 1,
            hasCardKey: false,
            requiresCardKey: false,
            isSignUp: false,
            hasRegisteredKeys: true
        )

        XCTAssertEqual(PostLoginGateEvaluator.nextAction(for: state), .showMain)
    }

    func test_showMainForReturningLoginWhenLocalKeysExistEvenWithoutBackendKeys() {
        let state = PostLoginGateState(
            hasSyncedVaults: false,
            hasVaults: false,
            mobileKeyCount: 1,
            requiredMobileKeyCount: 1,
            hasCardKey: false,
            requiresCardKey: false,
            isSignUp: false,
            hasRegisteredKeys: false
        )

        XCTAssertEqual(PostLoginGateEvaluator.nextAction(for: state), .showMain)
    }
}
