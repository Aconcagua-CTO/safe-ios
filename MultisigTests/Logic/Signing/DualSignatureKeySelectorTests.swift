import XCTest
@testable import Multisig
import CoreData

final class DualSignatureKeySelectorTests: XCTestCase {

    // MARK: - Helpers

    private func makeContext() -> NSManagedObjectContext {
        let model = NSManagedObjectModel.mergedModel(from: [Bundle(for: type(of: self))!, Bundle.main])!
        let container = NSPersistentContainer(name: "TestContainer", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            XCTAssertNil(error)
        }
        return container.viewContext
    }

    private func makeKey(context: NSManagedObjectContext,
                         address: String,
                         name: String,
                         type: KeyType) -> KeyInfo {
        let key = NSEntityDescription.insertNewObject(forEntityName: "KeyInfo", into: context) as! KeyInfo
        key.addressString = address
        key.name = name
        key.type = Int16(type.rawValue)
        return key
    }

    private func makeSafe(context: NSManagedObjectContext, owners: [KeyInfo]) -> Safe {
        let safe = NSEntityDescription.insertNewObject(forEntityName: "Safe", into: context) as! Safe
        owners.forEach {
            let ownerInfo = NSEntityDescription.insertNewObject(forEntityName: "SafeOwnerInfo", into: context) as! SafeOwnerInfo
            ownerInfo.address = $0.address
            ownerInfo.safe = safe
        }
        return safe
    }

    // MARK: - Tests

    func testLocalOwnerKeysFiltersAndSorts() {
        let ctx = makeContext()
        let k1 = makeKey(context: ctx, address: "0xB", name: "bKey", type: .deviceGenerated)
        let k2 = makeKey(context: ctx, address: "0xA", name: "aKey", type: .deviceImported)
        let k3 = makeKey(context: ctx, address: "0xC", name: "cKey", type: .tangem) // should be excluded

        let safe = makeSafe(context: ctx, owners: [k1, k2, k3])

        let result = DualSignatureKeySelector.localOwnerKeys(for: safe)
        XCTAssertEqual(result, [k2, k1]) // sorted by name then address
    }

    func testCardOwnerKeysFiltersCardsOnly() {
        let ctx = makeContext()
        let tangem = makeKey(context: ctx, address: "0x1", name: "Tangem", type: .tangem)
        let burner = makeKey(context: ctx, address: "0x2", name: "Burner", type: .burner)
        let local = makeKey(context: ctx, address: "0x3", name: "Local", type: .deviceImported)

        let safe = makeSafe(context: ctx, owners: [tangem, burner, local])

        let result = DualSignatureKeySelector.cardOwnerKeys(for: safe)
        XCTAssertEqual(result, [burner, tangem]) // sorted by name then address
    }
}

