//
//  VaultsRepository.swift
//  Multisig
//
//  Created on [Date]
//  Copyright © [Year] Gnosis Ltd. All rights reserved.
//

import Foundation
import CoreData

/**
 * Repository for syncing vaults from backend
 */
protocol VaultsRepository {
    /**
     * Sync vaults from backend and replace all local vaults
     * - Parameter completion: Completion handler with Result indicating success or failure
     */
    /// - Parameters:
    ///   - force: When true, bypasses the `AppSettings.useLocalVaults` guard so that manual refreshes can run even if automatic syncing is disabled.
    ///   - completion: Completion handler with Result indicating success or failure.
    func syncVaultsFromBackend(force: Bool, completion: @escaping (Result<Void, Error>) -> Void)
}

/**
 * Implementation of VaultsRepository
 * Fetches vaults from Aconcagua backend and syncs them to local CoreData database
 */
class VaultsRepositoryImpl: VaultsRepository {
    
    private let vaultsService: VaultsService
    private let delegatesService: DelegatesService
    private let authRepository: AuthRepository
    
    // Track if a sync is currently in progress to prevent concurrent syncs
    private var isSyncing: Bool = false
    private let syncQueue = DispatchQueue(label: "io.gnosis.multisig.vaultSync", qos: .userInitiated)
    
    init(vaultsService: VaultsService, delegatesService: DelegatesService, authRepository: AuthRepository) {
        self.vaultsService = vaultsService
        self.delegatesService = delegatesService
        self.authRepository = authRepository
    }
    
    func syncVaultsFromBackend(force: Bool = false, completion: @escaping (Result<Void, Error>) -> Void) {
        syncQueue.async { [weak self] in
            guard let self = self else {
                completion(.failure(NSError(domain: "VaultsRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Repository deallocated"])))
                return
            }
            
            VaultLogger.debug("syncVaultsFromBackend(force: \(force)) requested")
            
            // Check if a sync is already in progress
            if self.isSyncing {
                VaultLogger.warning("Vault sync already in progress, skipping new sync request (force=\(force))")
                completion(.success(()))
                return
            }
            
            // Mark sync as in progress
            self.isSyncing = true
            VaultLogger.info("Starting new vault sync operation (force=\(force))")
            
            self.syncVaultsFromBackendWithRetry(attempt: 1, force: force) { result in
                // Mark sync as complete
                self.syncQueue.async {
                    self.isSyncing = false
                    VaultLogger.info("Vault sync operation completed, ready for next sync")
                }
                completion(result)
            }
        }
    }
    
    private func syncVaultsFromBackendWithRetry(attempt: Int, force: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        // Check feature flag: if useLocalVaults is enabled, skip backend sync
        if AppSettings.useLocalVaults && !force {
            VaultLogger.info("Feature flag 'useLocalVaults' is enabled - skipping backend sync, using local vaults (force=false)")
            completion(.success(()))
            return
        } else if AppSettings.useLocalVaults && force {
            VaultLogger.info("Feature flag 'useLocalVaults' is enabled - forcing backend sync due to manual request")
        }
        
        let startTime = Date()
        
        // Get userId directly from AuthRepository (more reliable than cached preferences)
        guard let user = authRepository.getCurrentUser() else {
            VaultLogger.error("No user logged in - cannot sync vaults")
            let error = GSError.VaultSyncFailed(reason: "No user logged in")
            // Don't retry if there's no user - this is not a network error
            showErrorIfFinalAttempt(error: error, attempt: ApiConfig.vaultSyncMaxRetries)
            completion(.failure(error))
            return
        }
        let userId = user.uid
        
        VaultLogger.info("==================== STARTING VAULT SYNC (Attempt \(attempt)/\(ApiConfig.vaultSyncMaxRetries)) ====================")
        VaultLogger.info("User ID: \(userId)")
        VaultLogger.info("Timestamp: \(Date().timeIntervalSince1970)")
        VaultLogger.network("Backend URL: \(ApiConfig.vaultsApiURL.absoluteString)")
        VaultLogger.network("Full endpoint: \(ApiConfig.vaultsApiURL.absoluteString)by-user/\(userId)")
        
        #if DEBUG
        let environment = App.configuration.services.environment
        VaultLogger.debug("Environment: \(environment)")
        #endif
        
        // Store currently selected safe before sync
        let selectedSafeAddress: String?
        let selectedSafeChainId: String?
        do {
            if let selectedSafe = try Safe.getSelected() {
                selectedSafeAddress = selectedSafe.address
                selectedSafeChainId = selectedSafe.chain?.id
                VaultLogger.debug("Stored selected safe: \(selectedSafeAddress ?? "nil") on chain \(selectedSafeChainId ?? "nil")")
            } else {
                selectedSafeAddress = nil
                selectedSafeChainId = nil
                VaultLogger.debug("No safe currently selected")
            }
        } catch {
            VaultLogger.warning("Failed to get selected safe: \(error)")
            selectedSafeAddress = nil
            selectedSafeChainId = nil
        }
        
        // Fetch vaults from backend
        VaultLogger.network("Sending API request to backend...")
        vaultsService.getVaultsByUser(userId: userId, limit: nil, offset: nil) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let response):
                let requestTime = Date().timeIntervalSince(startTime)
                VaultLogger.network("API response received in \(String(format: "%.0f", requestTime * 1000))ms")
                VaultLogger.success("Received \(response.items.count) vault(s) from backend")
                
                #if DEBUG
                if let firstVault = response.items.first {
                    VaultLogger.debug("First vault sample: id=\(firstVault.id), name=\(firstVault.name), chainId=\(firstVault.chainId)")
                }
                #endif
                
                // Map backend vaults to Safe entities
                VaultLogger.info("Starting vault mapping process...")
                self.mapAndSyncVaults(
                    response.items,
                    currentUserId: userId,
                    selectedSafeAddress: selectedSafeAddress,
                    selectedSafeChainId: selectedSafeChainId,
                    startTime: startTime,
                    completion: completion
                )
                
            case .failure(let error):
                let errorTime = Date().timeIntervalSince(startTime)
                VaultLogger.error("Failed to fetch vaults after \(String(format: "%.0f", errorTime * 1000))ms (Attempt \(attempt)/\(ApiConfig.vaultSyncMaxRetries))", error: error)
                
                // Check if we should retry
                if attempt < ApiConfig.vaultSyncMaxRetries {
                    let retryDelay = ApiConfig.vaultSyncRetryDelay
                    VaultLogger.warning("Retrying in \(retryDelay) seconds...")
                    
                    // Schedule retry after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
                        self.syncVaultsFromBackendWithRetry(attempt: attempt + 1, force: force, completion: completion)
                    }
                } else {
                    // Final attempt failed, show error to user
                    VaultLogger.error("All \(ApiConfig.vaultSyncMaxRetries) retry attempts failed")
                    let syncError = GSError.VaultSyncFailed(reason: error.localizedDescription)
                    self.showErrorIfFinalAttempt(error: syncError, attempt: attempt)
                    completion(.failure(syncError))
                }
            }
        }
    }
    
    private func showErrorIfFinalAttempt(error: DetailedLocalizedError, attempt: Int) {
        if attempt >= ApiConfig.vaultSyncMaxRetries {
            DispatchQueue.main.async {
                SnackbarViewController.show(error.localizedDescription, duration: 5.0)
            }
        }
    }
    
    private func mapAndSyncVaults(
        _ vaultResponses: [VaultResponse],
        currentUserId: String,
        selectedSafeAddress: String?,
        selectedSafeChainId: String?,
        startTime: Date,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            do {
                let keyFor: (String, String) -> String = { address, chainId in
                    "\(address.lowercased())|\(chainId)"
                }
                
                // Map backend vaults to CoreData Safe entities
                var mappedSafes: [(address: String, name: String, chainId: String, chain: Chain, version: String?)] = []
                var skippedCount = 0
                var seenServerKeys = Set<String>()
                
                for (index, vault) in vaultResponses.enumerated() {
                    #if DEBUG
                    VaultLogger.debug("Processing vault \(index + 1)/\(vaultResponses.count)")
                    VaultLogger.debug("  ID: \(vault.id)")
                    VaultLogger.debug("  Name: \(vault.name)")
                    VaultLogger.debug("  ChainId: \(vault.chainId)")
                    VaultLogger.debug("  Version: \(vault.contractVersion ?? "nil")")
                    VaultLogger.debug("  State: \(vault.state)")
                    VaultLogger.debug("  Type: \(vault.vaultType ?? "nil")")
                    #endif
                    
                    // Extract address from id (handles both scoped IDs like "POLYGON:0x..." and plain addresses)
                    let addressString: String
                    if vault.id.contains(":") {
                        // Scoped ID format: "NETWORK:0x..." - extract the address part
                        let components = vault.id.components(separatedBy: ":")
                        addressString = components.last ?? vault.id
                    } else {
                        // Plain address format (backward compatibility)
                        addressString = vault.id
                    }
                    
                    #if DEBUG
                    if vault.id != addressString {
                        VaultLogger.debug("  Extracted address from scoped ID: \(addressString)")
                    }
                    #endif
                    
                    // Validate address format
                    guard let parsedAddress = Address(addressString) else {
                        VaultLogger.warning("Failed to parse vault \(index + 1): Invalid address format - \(vault.id) (extracted: \(addressString))")
                        skippedCount += 1
                        continue
                    }
                    
                    // Resolve chain ID (backend may send POLYGON id even for ARBITRUM vaults)
                    let resolvedChainId = chainId(for: vault)
                    if resolvedChainId != vault.chainId {
                        VaultLogger.debug("  Overriding backend chainId \(vault.chainId) with \(resolvedChainId) derived from network \(vault.contractNetwork ?? "nil")")
                    }
                    
                    // Find Chain entity (or restore from Safe Config cache)
                    let chain: Chain? = {
                        if let existing = Chain.by(resolvedChainId) {
                            return existing
                        }
                        if let cached = ChainManager.cachedChainInfo(for: resolvedChainId) {
                            VaultLogger.info("Chain missing for chainId \(resolvedChainId); restoring from Safe Config cache")
                            return Chain.createOrUpdate(cached.toSCGChain())
                        }
                        return nil
                    }()
                    guard let chain = chain else {
                        VaultLogger.warning("Failed to parse vault \(index + 1): Chain not found for chainId \(resolvedChainId)")
                        skippedCount += 1
                        continue
                    }
                    
                    guard let chainId = chain.id else {
                        VaultLogger.warning("Failed to parse vault \(index + 1): Chain has no identifier for chainId \(vault.chainId)")
                        skippedCount += 1
                        continue
                    }
                    
                    let normalizedAddress = parsedAddress.checksummed
                    let key = keyFor(normalizedAddress, chainId)
                    
                    if seenServerKeys.contains(key) {
                        VaultLogger.warning("Duplicate vault entry received for \(normalizedAddress) on chain \(chainId); skipping duplicate")
                        skippedCount += 1
                        continue
                    }
                    seenServerKeys.insert(key)

                    mappedSafes.append((
                        address: normalizedAddress,
                        name: vault.name,
                        chainId: chainId,
                        chain: chain,
                        version: vault.contractVersion
                    ))
                    
                    VaultLogger.success("Mapped vault \(index + 1): \(normalizedAddress.prefix(10))... -> Safe(\(vault.name), chain: \(chainId))")
                }
                
                VaultLogger.info("Prepared \(mappedSafes.count) vault(s) for sync (skipped: \(skippedCount))")
                
                let selectedKey: String? = {
                    guard
                        let address = selectedSafeAddress,
                        let chainId = selectedSafeChainId
                    else {
                        return nil
                    }
                    return keyFor(address, chainId)
                }()
                
                let existingSafes = try Safe.getAll()
                var existingSafesMap: [String: Safe] = [:]
                var duplicateLocalSafes = 0
                
                for safe in existingSafes where safe.address != Safe.demoAddress && !safe.isDelegate {
                    guard
                        let address = safe.address,
                        let chainId = safe.chain?.id
                    else {
                        VaultLogger.warning("Skipping local safe missing address or chain relationship")
                        continue
                    }
                    
                    let key = keyFor(address, chainId)
                    if existingSafesMap[key] != nil {
                        duplicateLocalSafes += 1
                        VaultLogger.warning("Duplicate local safe detected for \(address) on chain \(chainId); keeping the first instance")
                        continue
                    }
                    existingSafesMap[key] = safe
                }
                
                if duplicateLocalSafes > 0 {
                    VaultLogger.warning("Detected \(duplicateLocalSafes) duplicate local safe(s)")
                }
                
                var insertedCount = 0
                var updatedCount = 0
                var unchangedCount = 0
                var deletedCount = 0
                
                var updatedSafesNeedingSave: [Safe] = []
                var selectedSafeStillPresent = selectedKey == nil
                
                for mappedSafe in mappedSafes {
                    let chain = mappedSafe.chain
                    let key = keyFor(mappedSafe.address, mappedSafe.chainId)
                    
                    if let existingSafe = existingSafesMap.removeValue(forKey: key) {
                        var changed = false
                        
                        if existingSafe.name != mappedSafe.name {
                            existingSafe.name = mappedSafe.name
                            changed = true
                        }
                        if existingSafe.contractVersion != mappedSafe.version {
                            existingSafe.contractVersion = mappedSafe.version
                            changed = true
                        }
                        if existingSafe.safeStatus != .deployed {
                            existingSafe.safeStatus = .deployed
                            changed = true
                        }
                        if existingSafe.chain != chain {
                            existingSafe.chain = chain
                            changed = true
                        }
                        if existingSafe.isDelegate {
                            existingSafe.isDelegate = false
                            changed = true
                        }
                        if existingSafe.ownerName != nil {
                            existingSafe.ownerName = nil
                            changed = true
                        }
                        
                        if changed {
                            updatedSafesNeedingSave.append(existingSafe)
                            updatedCount += 1
                            VaultLogger.database("Updated safe: \(mappedSafe.address) on chain \(mappedSafe.chainId)")
                        } else {
                            unchangedCount += 1
                        }
                        
                        if key == selectedKey {
                            selectedSafeStillPresent = true
                        }
                    } else {
                        let shouldSelect = key == selectedKey
                        let safe = Safe.create(
                            address: mappedSafe.address,
                            version: mappedSafe.version,
                            name: mappedSafe.name,
                            chain: chain,
                            selected: shouldSelect,
                            status: .deployed
                        )
                        safe.isDelegate = false
                        safe.ownerName = nil
                        insertedCount += 1
                        
                        if shouldSelect {
                            selectedSafeStillPresent = true
                        }
                        
                        VaultLogger.database("Inserted safe: \(safe.address ?? mappedSafe.address) on chain \(mappedSafe.chainId)")
                    }
                }
                
                if !updatedSafesNeedingSave.isEmpty {
                    App.shared.coreDataStack.saveContext()
                    Safe.updateCachedNames()
                    VaultLogger.database("Saved \(updatedSafesNeedingSave.count) updated safe(s)")
                } else if insertedCount > 0 {
                    Safe.updateCachedNames()
                }
                
                if existingSafesMap.isEmpty == false {
                    VaultLogger.database("Removing \(existingSafesMap.count) stale local safe(s)")
                }
                
                for safe in existingSafesMap.values {
                    let key = keyFor(safe.address ?? "", safe.chain?.id ?? "")
                    Safe.remove(safe: safe)
                    deletedCount += 1
                    
                    if key == selectedKey {
                        selectedSafeStillPresent = false
                    }
                }
                
                let safesAfter = try Safe.getAll()
                let selectedAfter = try Safe.getSelected()
                
                if selectedAfter == nil, let firstSafe = safesAfter.first {
                    firstSafe.select()
                    VaultLogger.info("Selected fallback safe: \(firstSafe.address ?? "nil")")
                } else if selectedKey != nil && !selectedSafeStillPresent {
                    VaultLogger.info("Previously selected safe no longer available after sync")
                }
                
                if skippedCount > 0 {
                    VaultLogger.warning("Skipped \(skippedCount) vault(s) due to validation issues or duplicates")
                }
                
                let totalTime = Date().timeIntervalSince(startTime)
                VaultLogger.success("==================== SYNC COMPLETED ====================")
                VaultLogger.success("Total time: \(String(format: "%.0f", totalTime * 1000))ms")
                VaultLogger.success("Server vaults received: \(vaultResponses.count)")
                VaultLogger.success("Inserted: \(insertedCount), Updated: \(updatedCount), Unchanged: \(unchangedCount), Removed: \(deletedCount)")
                VaultLogger.success("Local safes total: \(safesAfter.count)")
                VaultLogger.success("Net change: \(insertedCount - deletedCount)")
                
                completion(.success(()))
                
            } catch {
                let errorTime = Date().timeIntervalSince(startTime)
                VaultLogger.error("==================== SYNC FAILED ====================")
                VaultLogger.error("Error after \(String(format: "%.0f", errorTime * 1000))ms: \(error.localizedDescription)", error: error)
                #if DEBUG
                VaultLogger.error("Exception type: \(type(of: error))")
                #endif
                completion(.failure(error))
            }
        }
    }

    private func syncDelegateVaults(
        currentUserId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        delegatesService.getVaultsByDelegateId(delegateId: currentUserId, limit: nil, offset: nil) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let response):
                DispatchQueue.main.async {
                    do {
                        let keyFor: (String, String) -> String = { address, chainId in
                            "\(address.lowercased())|\(chainId)"
                        }

                        var mappedSafes: [(address: String, name: String, chainId: String, chain: Chain, version: String?, ownerName: String?)] = []
                        var seenServerKeys = Set<String>()

                        for vault in response.items {
                            let addressString: String
                            if vault.id.contains(":") {
                                let components = vault.id.components(separatedBy: ":")
                                addressString = components.last ?? vault.id
                            } else {
                                addressString = vault.id
                            }

                            guard let parsedAddress = Address(addressString) else { continue }

                            let resolvedChainId = self.chainId(forDelegateVault: vault)
                            let chain: Chain? = {
                                if let existing = Chain.by(resolvedChainId) {
                                    return existing
                                }
                                if let cached = ChainManager.cachedChainInfo(for: resolvedChainId) {
                                    return Chain.createOrUpdate(cached.toSCGChain())
                                }
                                return nil
                            }()
                            guard let chain, let chainId = chain.id else { continue }

                            let normalizedAddress = parsedAddress.checksummed
                            let key = keyFor(normalizedAddress, chainId)
                            if seenServerKeys.contains(key) { continue }
                            seenServerKeys.insert(key)

                            mappedSafes.append((
                                address: normalizedAddress,
                                name: vault.name,
                                chainId: chainId,
                                chain: chain,
                                version: vault.contractVersion,
                                ownerName: vault.ownerName
                            ))
                        }

                        let existingSafes = try Safe.getAll()
                        var existingDelegatesMap: [String: Safe] = [:]
                        for safe in existingSafes where safe.address != Safe.demoAddress && safe.isDelegate {
                            guard let address = safe.address, let chainId = safe.chain?.id else { continue }
                            existingDelegatesMap[keyFor(address, chainId)] = safe
                        }

                        for mappedSafe in mappedSafes {
                            let key = keyFor(mappedSafe.address, mappedSafe.chainId)
                            if let existingSafe = existingDelegatesMap.removeValue(forKey: key) {
                                existingSafe.name = mappedSafe.name
                                existingSafe.contractVersion = mappedSafe.version
                                existingSafe.safeStatus = .deployed
                                existingSafe.chain = mappedSafe.chain
                                existingSafe.isDelegate = true
                                existingSafe.ownerName = mappedSafe.ownerName
                            } else {
                                let safe = Safe.create(
                                    address: mappedSafe.address,
                                    version: mappedSafe.version,
                                    name: mappedSafe.name,
                                    chain: mappedSafe.chain,
                                    selected: false,
                                    status: .deployed
                                )
                                safe.isDelegate = true
                                safe.ownerName = mappedSafe.ownerName
                            }
                        }

                        for safe in existingDelegatesMap.values {
                            Safe.remove(safe: safe)
                        }

                        App.shared.coreDataStack.saveContext()
                        Safe.updateCachedNames()
                        completion(.success(()))
                    } catch {
                        completion(.failure(error))
                    }
                }
            }
        }
    }
}

// MARK: - Helpers

private extension VaultsRepository {
    func chainId(for vault: VaultResponse) -> String {
        guard let networkName = vault.contractNetwork?.uppercased() else {
            return vault.chainId
        }
        if let mapped = vaultNetworkNameToChainId[networkName] {
            return mapped
        }
        return vault.chainId
    }

    func chainId(forDelegateVault vault: DelegateVaultResponse) -> String {
        guard let networkName = vault.contractNetwork?.uppercased() else {
            return vault.chainId
        }
        if let mapped = vaultNetworkNameToChainId[networkName] {
            return mapped
        }
        return vault.chainId
    }
}

private let vaultNetworkNameToChainId: [String: String] = [
    "ARBITRUM": Chain.ChainID.arbitrum,
    "POLYGON": Chain.ChainID.polygon,
    "ETHEREUM": Chain.ChainID.ethereumMainnet,
    "GNOSIS": Chain.ChainID.gnosis,
    "BSC": Chain.ChainID.bsc,
    "AVALANCHE": Chain.ChainID.avalanche,
    "OPTIMISM": Chain.ChainID.optimism,
    "ROOTSTOCK": Chain.ChainID.rootstock,
    "BASE": Chain.ChainID.base,
    "PLASMA": Chain.ChainID.plasma
]

