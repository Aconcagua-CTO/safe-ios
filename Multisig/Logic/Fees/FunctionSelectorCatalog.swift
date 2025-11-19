//
//  FunctionSelectorCatalog.swift
//  Multisig
//
//  Created by GPT-5 Codex on 15.11.25.
//

import Foundation

final class FunctionSelectorCatalog {
    struct Entry: Decodable {
        let selector: String
        let protocolName: String
        let functionName: String
        let functionSignature: String
        let amountParameterLocation: String?
        let amountParameterIndex: Int?
        let requiresApproval: Bool
        let contractAddresses: [String: String]?
        let note: String?

        private enum CodingKeys: String, CodingKey {
            case selector
            case protocolName
            case legacyProtocol = "protocol"
            case functionName
            case functionSignature
            case amountParameterLocation
            case amountParameterIndex
            case requiresApproval
            case contractAddresses
            case note
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            selector = try container.decode(String.self, forKey: .selector)
            if let protocolName = try container.decodeIfPresent(String.self, forKey: .protocolName) {
                self.protocolName = protocolName
            } else if let legacyProtocol = try container.decodeIfPresent(String.self, forKey: .legacyProtocol) {
                self.protocolName = legacyProtocol
            } else {
                throw DecodingError.keyNotFound(
                    CodingKeys.protocolName,
                    DecodingError.Context(codingPath: container.codingPath,
                                          debugDescription: "Missing protocol/protocolName value")
                )
            }
            functionName = try container.decode(String.self, forKey: .functionName)
            functionSignature = try container.decode(String.self, forKey: .functionSignature)
            amountParameterLocation = try container.decodeIfPresent(String.self, forKey: .amountParameterLocation)
            amountParameterIndex = try container.decodeIfPresent(Int.self, forKey: .amountParameterIndex)
            requiresApproval = try container.decodeIfPresent(Bool.self, forKey: .requiresApproval) ?? false
            contractAddresses = try container.decodeIfPresent([String: String].self, forKey: .contractAddresses)
            note = try container.decodeIfPresent(String.self, forKey: .note)
        }

        var normalizedSelector: Data? {
            let cleaned = selector.trimmingCharacters(in: .whitespacesAndNewlines)
            let data = Data(ethHex: cleaned)
            guard !data.isEmpty else { return nil }
            let length = Swift.min(4, data.count)
            return data.subdata(in: 0..<length)
        }
    }

    struct Root: Decodable {
        let functionSelectors: [Entry]
        let notes: [String: String]?
    }

    static let shared = FunctionSelectorCatalog()

    private let entriesBySelector: [Data: Entry]

    init(bundle: Bundle = .main) {
        if let loaded = FunctionSelectorCatalog.loadEntries(bundle: bundle) {
            entriesBySelector = loaded
        } else {
            entriesBySelector = [:]
        }
    }

    convenience init?(jsonURL: URL) {
        guard let loaded = FunctionSelectorCatalog.loadEntries(url: jsonURL) else { return nil }
        self.init(dictionary: loaded)
    }

    private init(dictionary: [Data: Entry]) {
        entriesBySelector = dictionary
    }

    private static func loadEntries(bundle: Bundle) -> [Data: Entry]? {
        guard let url = bundle.url(forResource: "function-selectors", withExtension: "json") else {
            TransactionFeeLogger.warning("function-selectors.json not found in bundle – fee batching will be disabled.")
            return nil
        }
        return loadEntries(url: url)
    }

    private static func loadEntries(url: URL) -> [Data: Entry]? {
        do {
            let data = try Data(contentsOf: url)
            let lookup = try decodeEntries(from: data)
            return lookup
        } catch {
            TransactionFeeLogger.error("Failed to parse function-selectors.json – \(error.localizedDescription)", error: error)
            return nil
        }
    }

    private static func decodeEntries(from data: Data) throws -> [Data: Entry] {
        let decoder = JSONDecoder()
        let root = try decoder.decode(Root.self, from: data)
        var lookup = [Data: Entry]()
        for entry in root.functionSelectors {
            guard let selector = entry.normalizedSelector else {
                TransactionFeeLogger.warning("Skipping selector entry for \(entry.functionSignature) – invalid selector: \(entry.selector)")
                continue
            }
            lookup[selector] = entry
        }
        TransactionFeeLogger.debug("Loaded \(lookup.count) function selector entries for fee batching.")
        return lookup
    }

    func entry(for selector: Data) -> Entry? {
        let length = Swift.min(4, selector.count)
        let slice = selector.subdata(in: 0..<length)
        return entriesBySelector[slice]
    }

    func isExpectedContract(_ entry: Entry,
                            transactionAddress: AddressString,
                            chainId: String) -> Bool {
        guard let mapping = entry.contractAddresses, !mapping.isEmpty else {
            return true
        }
        guard let expectedAddress = mapping[chainId] else {
            TransactionFeeLogger.debug("Selector \(entry.functionSignature) does not provide mapping for chain \(chainId); skipping strict address validation.")
            return true
        }
        guard let normalized = Address(expectedAddress) else {
            TransactionFeeLogger.warning("Invalid expected address '\(expectedAddress)' for selector \(entry.functionSignature); skipping validation.")
            return true
        }
        return normalized.checksummed.caseInsensitiveCompare(transactionAddress.address.checksummed) == .orderedSame
    }
}

