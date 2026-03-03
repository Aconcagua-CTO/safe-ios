//
//  Safe+CoreDataProperties.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 23.02.22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//
//

import Foundation
import CoreData


extension Safe {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Safe> {
        return NSFetchRequest<Safe>(entityName: "Safe")
    }

    @NSManaged public var additionDate: Date?
    @NSManaged public var address: String?
    @NSManaged public var contractVersion: String?
    @NSManaged public var isDelegate: Bool
    @NSManaged public var name: String?
    @NSManaged public var ownerName: String?
    @NSManaged public var sessionTopics: String?
    @NSManaged public var status: Int16
    @NSManaged public var chain: Chain?
    @NSManaged public var selection: Selection?
}

extension Safe : Identifiable {

}
