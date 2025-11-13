//
//  VaultResponse.swift
//  Multisig
//
//  Created on [Date]
//  Copyright © [Year] Gnosis Ltd. All rights reserved.
//

import Foundation

/**
 * Backend response model for a single vault
 * Maps from Aconcagua backend vault structure to iOS Safe model
 */
struct VaultResponse: Codable {
    let id: String                          // Vault address (hex string)
    let name: String                       // User-friendly name
    let chainId: String                    // Numeric chain ID as string (137, 30, etc.)
    let contractVersion: String?           // Contract version (nullable)
    let state: Int                         // Vault state (1 = active, 0 = inactive, etc.)
    let vaultType: String?                 // Type of vault (savings, credit, etc.)
    let contractNetwork: String?          // Network name (POLYGON, ROOTSTOCK, etc.)
}

/**
 * Backend response model for list of vaults
 * Wraps the array of vaults in an items property
 */
struct VaultsListResponse: Codable {
    let items: [VaultResponse]
    let total: Int?
    let limit: Int?
    let offset: Int?
}

