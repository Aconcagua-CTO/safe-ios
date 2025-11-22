import XCTest
@testable import Multisig

final class BurnerAPDUTests: XCTestCase {
    
    func testSelectCoreCommandMatchesInfoPlistIdentifier() throws {
        let expectedIdentifier = BurnerAPDU.haloAid
            .map { String(format: "%02X", $0) }
            .joined()
        
        let infoURL = repositoryRoot()
            .appendingPathComponent("Multisig")
            .appendingPathComponent("Info.plist")
        
        let infoData = try Data(contentsOf: infoURL)
        let plist = try PropertyListSerialization.propertyList(from: infoData,
                                                               options: [],
                                                               format: nil)
        guard
            let dict = plist as? [String: Any],
            let identifiers = dict["com.apple.developer.nfc.readersession.iso7816.select-identifiers"] as? [String]
        else {
            XCTFail("Unable to read NFC identifiers from Info.plist")
            return
        }
        
        XCTAssertTrue(identifiers.contains(expectedIdentifier),
                      "HaLo AID \(expectedIdentifier) is missing from Info.plist")
        
        var expectedCommand: [UInt8] = [0x00, 0xA4, 0x04, 0x00, 0x07]
        expectedCommand.append(contentsOf: BurnerAPDU.haloAid)
        expectedCommand.append(0x00)
        
        XCTAssertEqual(BurnerAPDU.selectCoreCommand, Data(expectedCommand),
                       "select_core APDU does not match expected bytes")
    }
    
    private func repositoryRoot(file: StaticString = #filePath) -> URL {
        var url = URL(fileURLWithPath: "\(file)")
        for _ in 0..<4 {
            url.deleteLastPathComponent()
        }
        return url
    }
}

