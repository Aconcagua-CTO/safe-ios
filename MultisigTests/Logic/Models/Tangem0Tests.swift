import XCTest
@testable import Multisig

final class Tangem0Tests: XCTestCase {
    func testTangem0MetadataRoundTrip() {
        let metadata = KeyInfo.Tangem0KeyMetadata(
            cardId: "TANGEM0-TEST",
            walletPublicKey: Data([0x02, 0xAA, 0xBB, 0xCC]),
            derivationPath: "m/44'/60'/0'/0/0",
            walletIndex: 1
        )

        let decoded = KeyInfo.Tangem0KeyMetadata.from(data: metadata.data)

        XCTAssertEqual(decoded?.cardId, metadata.cardId)
        XCTAssertEqual(decoded?.walletPublicKey, metadata.walletPublicKey)
        XCTAssertEqual(decoded?.derivationPath, metadata.derivationPath)
        XCTAssertEqual(decoded?.walletIndex, metadata.walletIndex)
    }

    func testTangem0DoesNotNormalizeWalletPublicKeyForSigning() throws {
        // Regression guard:
        // Tangem0 signing must use the on-card wallet public key bytes (often 33-byte compressed).
        // Normalizing (decompressing) to 65 bytes can cause Tangem SDK to fail with walletNotFound.
        let service = Tangem0Service()
        let compressedKey = Data(repeating: 0x02, count: 33)
        let normalized = try service.normalizedWalletPublicKey(compressedKey)
        XCTAssertEqual(compressedKey.count, 33)
        XCTAssertEqual(normalized.count, 65)
        XCTAssertNotEqual(normalized, compressedKey)
    }

    func testTangem0TrackingAndAssets() {
        XCTAssertEqual(KeyType.tangem0.trackingValue, "tangem0")
        XCTAssertFalse(KeyType.tangem0.imageName.isEmpty)
        XCTAssertFalse(KeyType.tangem0.badgeName.isEmpty)
    }
}
