//
//  TokenWhitelist+CoreDataProperties.swift
//  Multisig
//

import Foundation
import CoreData

extension TokenWhitelist {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<TokenWhitelist> {
        NSFetchRequest<TokenWhitelist>(entityName: "TokenWhitelist")
    }

    @NSManaged public var id: String
    @NSManaged public var tokenSymbol: String?
    @NSManaged public var tokenName: String?
    @NSManaged public var tokenType: String?
    @NSManaged public var tokenCategory: String?
    @NSManaged public var wrapLabel: String?
    @NSManaged public var network: String?
    @NSManaged public var networkAddress: String?
    @NSManaged public var decimals: Int16
    @NSManaged public var chainId: String?
    @NSManaged public var enabled: Bool
    @NSManaged public var stable: Bool
    @NSManaged public var rebasing: Bool
    @NSManaged public var native: Bool
    @NSManaged public var erc20: Bool
    @NSManaged public var image: String?
    @NSManaged public var descriptionText: String?
    @NSManaged public var priceSource: String?
    @NSManaged public var priceSourceParam: String?

    // Yield enrichment (MoneyMarket / Aave)
    @NSManaged public var yieldSource: String?
    @NSManaged public var aaveMarketPoolAddress: String?
    @NSManaged public var aaveUnderlyingTokenAddress: String?
    @NSManaged public var aaveMarketName: String?
}

extension TokenWhitelist: Identifiable {}


