//
//  BurnerCommandParserTests.swift
//  MultisigTests
//
//  Created by GPT-5.1 Codex.
//

import XCTest
import BigInt
@testable import Multisig

final class BurnerCommandParserTests: XCTestCase {
    func testParsePublicKeysDecodesMultipleSlots() throws {
        var key1Bytes: [UInt8] = [0x04]
        key1Bytes.append(contentsOf: (1...64).map { UInt8($0) })
        var key2Bytes: [UInt8] = [0x04]
        key2Bytes.append(contentsOf: (65...128).map { UInt8($0 & 0xFF) })
        
        let key1 = Data(key1Bytes)
        let key2 = Data(key2Bytes)
        
        var payload = Data([UInt8(key1.count)])
        payload.append(key1)
        payload.append(UInt8(key2.count))
        payload.append(key2)
        payload.append(0x00) // terminator
        
        let slots = try BurnerCommandParser.parsePublicKeys(from: payload)
        XCTAssertEqual(slots.count, 2)
        XCTAssertEqual(slots.first?.slot, 1)
        XCTAssertEqual(slots.last?.slot, 2)
        XCTAssertEqual(slots.first?.publicKey, key1)
        XCTAssertEqual(slots.last?.publicKey, key2)
        
        let expectedAddress1 = try expectedAddress(for: key1)
        let expectedAddress2 = try expectedAddress(for: key2)
        XCTAssertEqual(slots[0].ethereumAddress, expectedAddress1)
        XCTAssertEqual(slots[1].ethereumAddress, expectedAddress2)
    }
    
    func testCanonicalizeSignatureNormalizesSComponent() throws {
        let r = Data([0x01])
        let rEncoded = Data([0x02, UInt8(r.count)]) + r
        // intentionally over-sized s value (> curve order)
        let sRaw = Data(repeating: 0xFF, count: 33)
        let sEncoded = Data([0x02, UInt8(sRaw.count)]) + sRaw
        let der = Data([0x30, UInt8(rEncoded.count + sEncoded.count)]) + rEncoded + sEncoded
        
        let canonical = try BurnerCommandParser.canonicalizeSignature(der)
        XCTAssertEqual(canonical.count, 64)
        
        let rPart = canonical.prefix(32)
        let sPart = canonical.suffix(32)
        
        XCTAssertEqual(rPart, Data(repeating: 0x00, count: 31) + Data([0x01]))
        
        let order = BigUInt("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141", radix: 16)!
        var expectedS = BigUInt(sRaw)
        expectedS = expectedS % order
        if expectedS > order / 2 {
            expectedS = order - expectedS
        }
        let expectedSData = expectedS.serialize().leftPadded(to: 32)
        XCTAssertEqual(sPart, expectedSData)
    }
    
    // MARK: - Helpers
    
    private func expectedAddress(for key: Data) throws -> Address {
        let trimmedBytes = Array(key.dropFirst())
        let hash = EthHasher.hash(Data(trimmedBytes))
        let suffixSlice: Data = hash.suffix(20)
        let addressBytes = Data(Array(suffixSlice))
        return Address(exactly: addressBytes)
    }
}

final class BurnerCardIdentityValidationTests: XCTestCase {
    func testValidateSucceedsWhenIdentifiersMatchIgnoringCase() {
        let identity = BurnerService.BurnerCardIdentity(cardId: "A02.03.000152.3E77AA4A",
                                                        tagIdentifier: "07581613",
                                                        isAttestedCardId: true)
        XCTAssertNoThrow(
            try BurnerService.validateCardIdentity(expectedCardId: "a02.03.000152.3e77aa4a",
                                                   expectedTagIdentifier: "07581613",
                                                   actual: identity)
        )
    }
    
    func testValidateThrowsWhenTagIdentifierMismatches() {
        let identity = BurnerService.BurnerCardIdentity(cardId: "A02.03.000152.3E77AA4A",
                                                        tagIdentifier: "07581613",
                                                        isAttestedCardId: true)
        XCTAssertThrowsError(
            try BurnerService.validateCardIdentity(expectedCardId: identity.cardId,
                                                   expectedTagIdentifier: "DEADBEEF",
                                                   actual: identity)
        ) { error in
            guard case BurnerService.BurnerServiceError.cardMismatch(let expected, let actual) = error else {
                return XCTFail("Unexpected error \(error)")
            }
            XCTAssertEqual(expected, "DEADBEEF")
            XCTAssertEqual(actual, "07581613")
        }
    }
    
    func testValidateThrowsWhenCardIdMismatchesAndNoTagIdentifierProvided() {
        let identity = BurnerService.BurnerCardIdentity(cardId: "A02.03.000152.3E77AA4A",
                                                        tagIdentifier: "07581613",
                                                        isAttestedCardId: true)
        XCTAssertThrowsError(
            try BurnerService.validateCardIdentity(expectedCardId: "B02.99.999999.00000000",
                                                   expectedTagIdentifier: nil,
                                                   actual: identity)
        ) { error in
            guard case BurnerService.BurnerServiceError.cardMismatch(let expected, let actual) = error else {
                return XCTFail("Unexpected error \(error)")
            }
            XCTAssertEqual(expected, "B02.99.999999.00000000")
            XCTAssertEqual(actual, identity.cardId)
        }
    }
    
    func testValidateSkipsCardCheckWhenTagMatchesButCardIdNotAttested() {
        let identity = BurnerService.BurnerCardIdentity(cardId: "07581613",
                                                        tagIdentifier: "07581613",
                                                        isAttestedCardId: false)
        XCTAssertNoThrow(
            try BurnerService.validateCardIdentity(expectedCardId: "A02.03.000152.3E77AA4A",
                                                   expectedTagIdentifier: "07581613",
                                                   actual: identity)
        )
    }
    
    func testValidateFailsWhenAttestedMissingAndNoTagIdentifier() {
        let identity = BurnerService.BurnerCardIdentity(cardId: "07581613",
                                                        tagIdentifier: "07581613",
                                                        isAttestedCardId: false)
        XCTAssertThrowsError(
            try BurnerService.validateCardIdentity(expectedCardId: "A02.03.000152.3E77AA4A",
                                                   expectedTagIdentifier: nil,
                                                   actual: identity)
        )
    }
}

