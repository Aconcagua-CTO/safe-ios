//
//  AddressBookEntry.swift
//  Multisig
//
//  Created by Andrey Scherbovich on 20/10/21.
//  Copyright © 2021 Gnosis Ltd. All rights reserved.
//

import Foundation
import CoreData

// "address:chainId" -> name
fileprivate var cachedNames = [String: String]()

extension AddressBookEntry {
    var displayAddress: String { address! }
    var addressValue: Address { Address(address!)! }
    var browserURL: URL { chain!.browserURL(address: displayAddress) }
    
    static var count: Int {
        let context = App.shared.coreDataStack.viewContext
        return (try? context.count(for: AddressBookEntry.fetchRequest().all())) ?? 0
    }

    static var all: [AddressBookEntry] {
        let context = App.shared.coreDataStack.viewContext
        return (try? context.fetch(AddressBookEntry.fetchRequest().all())) ?? []
    }

    static func by(address: String, chainId: String) -> AddressBookEntry? {
        dispatchPrecondition(condition: .onQueue(.main))
        let context = App.shared.coreDataStack.viewContext
        let fr = AddressBookEntry.fetchRequest().by(address: address, chainId: chainId)
        return try? context.fetch(fr).first
    }

    static func by(chainId: String) -> [AddressBookEntry]? {
        dispatchPrecondition(condition: .onQueue(.main))
        let context = App.shared.coreDataStack.viewContext
        let fr = AddressBookEntry.fetchRequest().by(chainId: chainId)
        return try? context.fetch(fr)
    }

    static func updateCachedNames() {
        guard let entities = try? AddressBookEntry.getAll() else { return }

        cachedNames = entities.reduce(into: [String: String]()) { names, entry in
            let chainId = entry.chain != nil ? entry.chain!.id! : Chain.ChainID.ethereumMainnet
            let key = "\(entry.displayAddress):\(chainId)"
            names[key] = entry.name!
        }
    }

    static func cachedName(by address: AddressString, chainId: String) -> String? {
        let key = "\(address.description):\(chainId)"
        return cachedNames[key]
    }

    public override func awakeFromInsert() {
        super.awakeFromInsert()
        additionDate = Date()
    }

    static func getAll() throws -> [AddressBookEntry] {
        do {
            let context = App.shared.coreDataStack.viewContext
            let fr = AddressBookEntry.fetchRequest().all()
            let entities = try context.fetch(fr)
            return entities
        } catch {
            throw GSError.DatabaseError(reason: error.localizedDescription)
        }
    }

    static let supportedChainIDs: [String] = [
        Chain.ChainID.ethereumMainnet,
        Chain.ChainID.base,
        Chain.ChainID.polygon,
        Chain.ChainID.bsc,
        Chain.ChainID.arbitrum,
        Chain.ChainID.plasma,
        Chain.ChainID.gnosis,
        Chain.ChainID.rootstock,
    ]

    static func addOrUpdate(_ address: String, chain: Chain, name: String) {
        if Self.exists(address, chainId: chain.id!) {
            Self.update(address, chainId: chain.id!, name: name)
        } else {
            Self.create(address: address, name: name, chain: chain)
        }
    }

    static func addOrUpdateAllSupportedChains(_ address: String, name: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        let context = App.shared.coreDataStack.viewContext
        for chainId in supportedChainIDs {
            guard let chain = Chain.by(chainId) else { continue }
            if let entry = by(address: address, chainId: chainId) {
                entry.name = name
            } else {
                let entry = AddressBookEntry(context: context)
                entry.address = address
                entry.name = name
                entry.chain = chain
            }
        }
        App.shared.coreDataStack.saveContext()
        updateCachedNames()
        NotificationCenter.default.post(name: .addressbookChanged, object: nil)
    }

    static func updateAllChains(_ address: String, name: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        for chainId in supportedChainIDs {
            guard let entry = by(address: address, chainId: chainId) else { continue }
            entry.name = name
        }
        App.shared.coreDataStack.saveContext()
        updateCachedNames()
        NotificationCenter.default.post(name: .addressbookChanged, object: nil)
    }

    static func removeFromAllChains(_ address: String) {
        let context = App.shared.coreDataStack.viewContext
        for chainId in supportedChainIDs {
            guard let entry = by(address: address, chainId: chainId) else { continue }
            context.delete(entry)
        }
        App.shared.coreDataStack.saveContext()
        updateCachedNames()
        NotificationCenter.default.post(name: .addressbookChanged, object: nil)
    }

    static func existsOnAnySupportedChain(_ address: String) -> Bool {
        supportedChainIDs.contains { by(address: address, chainId: $0) != nil }
    }

    static func exists(_ address: String, chainId: String) -> Bool {
        by(address: address, chainId: chainId) != nil
    }

    static func uniqueEntries() -> [AddressBookEntry] {
        guard let entries = try? getAll() else { return [] }
        var seen = Set<String>()
        var unique = [AddressBookEntry]()
        for entry in entries.sorted(by: { ($0.name ?? "") < ($1.name ?? "") }) {
            let addr = entry.displayAddress.lowercased()
            if seen.insert(addr).inserted {
                unique.append(entry)
            }
        }
        return unique
    }

    static func update(_ address: String, chainId: String, name: String) {
        dispatchPrecondition(condition: .onQueue(.main))

        guard let entry = by(address: address, chainId: chainId) else { return }
        entry.name = name
        App.shared.coreDataStack.saveContext()
        AddressBookEntry.updateCachedNames()

        NotificationCenter.default.post(name: .addressbookChanged, object: nil)
    }

    @discardableResult
    static func create(address: String, name: String, chain: Chain) -> AddressBookEntry {
        dispatchPrecondition(condition: .onQueue(.main))
        let context = App.shared.coreDataStack.viewContext

        let entry = AddressBookEntry(context: context)
        entry.address = address
        entry.name = name
        entry.chain = chain

        App.shared.coreDataStack.saveContext()

        updateCachedNames()

        NotificationCenter.default.post(name: .addressbookChanged, object: nil)

        return entry
    }

    @discardableResult
    static func create(address: String, name: String, chainInfo: SCGModels.Chain) -> AddressBookEntry {
        let chain = Chain.createOrUpdate(chainInfo)
        return AddressBookEntry.create(address: address, name: name, chain: chain)
    }

    @discardableResult
    static func from(csvString: String) -> AddressBookEntry? {
        let attributes = csvString.components(separatedBy: ",")
        guard attributes.count == 3,
              let _ = Address(attributes[0]),
              let chain = Chain.by(attributes[2])
        else { return nil }

        if let entry = AddressBookEntry.by(address: attributes[0], chainId: chain.id!) {
            entry.update(name: attributes[1])
            return entry
        }

        return AddressBookEntry.create(address: attributes[0], name: attributes[1], chain: chain)
    }

    func update(name: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        self.name = name
        App.shared.coreDataStack.saveContext()
        AddressBookEntry.updateCachedNames()
        NotificationCenter.default.post(name: .addressbookChanged, object: nil)
    }

    static func remove(entry: AddressBookEntry) {
        let context = App.shared.coreDataStack.viewContext
        context.delete(entry)
        App.shared.coreDataStack.saveContext()
        updateCachedNames()
        NotificationCenter.default.post(name: .addressbookChanged, object: nil)
    }

    static func removeAll() throws {
        for entry in all {
            remove(entry: entry)
        }

        NotificationCenter.default.post(name: .addressbookChanged, object: nil)
    }
}

extension AddressBookEntry {
    func update(address: Address, name: String) {
        self.name = name
    }

    var csv: String {
        [addressValue.checksummed, name!.contains(",") ? "\"\(name!)\"" : name!, chain!.id!].joined(separator: ",")
    }
}

extension AddressBookEntry {
    static func exportToCSV() -> String? {
        let unique = uniqueEntries()
        guard !unique.isEmpty else { return nil }
        return (["address,name,chainId"] + unique.map { $0.csv }).joined(separator: "\n")
    }

    static func importFrom(csv: String) -> (numberOfAdded: Int, numberOfUpdated: Int) {
        var numberOfAdded: Int = 0
        var numberOfUpdated: Int = 0
        var processedAddresses = Set<String>()
        let entites = csv.split(whereSeparator: \.isNewline).dropFirst()
        entites.forEach { entry in
            var values: [String] = []
            if entry.contains("\"") {
                values = entry.components(separatedBy: "\",")
                    .map { $0.components(separatedBy: ",\"") }
                    .flatMap { $0 }
            } else {
                values = entry.components(separatedBy: ",")
            }

            guard values.count == 3,
                  let _ = Address(values[0]) else { return }
            let addr = values[0]
            guard processedAddresses.insert(addr.lowercased()).inserted else { return }
            let wasExisting = existsOnAnySupportedChain(addr)
            addOrUpdateAllSupportedChains(addr, name: values[1])
            if wasExisting {
                numberOfUpdated += 1
            } else {
                numberOfAdded += 1
            }
        }

        return (numberOfAdded, numberOfUpdated)
    }
}

extension NSFetchRequest where ResultType == AddressBookEntry {
    func all() -> Self {
        sortDescriptors = [NSSortDescriptor(keyPath: \AddressBookEntry.name, ascending: true)]
        return self
    }

    func by(address: String, chainId: String) -> Self {
        sortDescriptors = []
        predicate = NSPredicate(format: "address == %@ AND chain.id == %@", address, chainId)
        fetchLimit = 1
        return self
    }

    func by(chainId: String) -> Self {
        sortDescriptors = []
        predicate = NSPredicate(format: "chain.id == %@", chainId)
        return self
    }
}
