import XCTest
@testable import Multisig

final class TangemDerivationPathPolicyTests: XCTestCase {
    func testDefaultDerivationPathIsNil() {
        let wallet = TangemCardSummary.Wallet(
            index: 0,
            curve: .secp256k1,
            publicKey: Data([0x02, 0xAA, 0xBB, 0xCC]),
            chainCode: nil,
            isImported: false,
            remainingSignatures: nil
        )

        XCTAssertNil(TangemDerivationPathPolicy.defaultDerivationPath(for: wallet))
    }
}


