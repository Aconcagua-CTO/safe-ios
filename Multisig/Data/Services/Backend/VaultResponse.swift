//
//  VaultResponse.swift
//  Multisig
//
//  Created on [Date]
//  Copyright © 2024 Gnosis Ltd. All rights reserved.
//

import Foundation

/**
 * Backend response model for a single vault
 * Maps from Aconcagua backend vault structure to iOS Safe model
 */
struct VaultResponse: Codable {
    let id: String                          // Vault address (hex string)
    let name: String                       // User-friendly name
    let vaultName: String?                 // Optional custom vault name (stored in backend)
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

/**
 * Backend response model for vaults where current user is a delegate
 */
struct DelegateVaultResponse: Codable {
    let id: String
    let name: String
    let chainId: String
    let contractVersion: String?
    let state: Int
    let vaultType: String?
    let contractNetwork: String?
    let ownerUserId: String?
    let ownerName: String?
    let companyId: String?
    let delegateId: String?
}

struct DelegateVaultsListResponse: Codable {
    let items: [DelegateVaultResponse]
    let total: Int?
    let limit: Int?
    let offset: Int?
}

