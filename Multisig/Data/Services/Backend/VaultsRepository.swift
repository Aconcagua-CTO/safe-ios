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
    func syncVaultsFromBackend(completion: @escaping (Result<Void, Error>) -> Void)
}

/**
 * Implementation of VaultsRepository
 * Fetches vaults from Aconcagua backend and syncs them to local CoreData database
 */
class VaultsRepositoryImpl: VaultsRepository {
    
    private let vaultsService: VaultsService
    private let authRepository: AuthRepository
    
    // Track if a sync is currently in progress to prevent concurrent syncs
    private var isSyncing: Bool = false
    private let syncQueue = DispatchQueue(label: "io.gnosis.multisig.vaultSync", qos: .userInitiated)
    
    init(vaultsService: VaultsService, authRepository: AuthRepository) {
        self.vaultsService = vaultsService
        self.authRepository = authRepository
    }
    
    func syncVaultsFromBackend(completion: @escaping (Result<Void, Error>) -> Void) {
        syncQueue.async { [weak self] in
            guard let self = self else {
                completion(.failure(NSError(domain: "VaultsRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Repository deallocated"])))
                return
            }
            
            // Check if a sync is already in progress
            if self.isSyncing {
                VaultLogger.warning("Vault sync already in progress, skipping new sync request")
                completion(.success(()))
                return
            }
            
            // Mark sync as in progress
            self.isSyncing = true
            VaultLogger.info("Starting new vault sync operation")
            
            self.syncVaultsFromBackendWithRetry(attempt: 1) { result in
                // Mark sync as complete
                self.syncQueue.async {
                    self.isSyncing = false
                    VaultLogger.info("Vault sync operation completed, ready for next sync")
                }
                completion(result)
            }
        }
    }
    
    private func syncVaultsFromBackendWithRetry(attempt: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        // Check feature flag: if useLocalVaults is enabled, skip backend sync
        if AppSettings.useLocalVaults {
            VaultLogger.info("Feature flag 'useLocalVaults' is enabled - skipping backend sync, using local vaults")
            completion(.success(()))
            return
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
                self.mapAndSyncVaults(response.items, selectedSafeAddress: selectedSafeAddress, selectedSafeChainId: selectedSafeChainId, startTime: startTime, completion: completion)
                
            case .failure(let error):
                let errorTime = Date().timeIntervalSince(startTime)
                VaultLogger.error("Failed to fetch vaults after \(String(format: "%.0f", errorTime * 1000))ms (Attempt \(attempt)/\(ApiConfig.vaultSyncMaxRetries))", error: error)
                
                // Check if we should retry
                if attempt < ApiConfig.vaultSyncMaxRetries {
                    let retryDelay = ApiConfig.vaultSyncRetryDelay
                    VaultLogger.warning("Retrying in \(retryDelay) seconds...")
                    
                    // Schedule retry after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
                        self.syncVaultsFromBackendWithRetry(attempt: attempt + 1, completion: completion)
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
        selectedSafeAddress: String?,
        selectedSafeChainId: String?,
        startTime: Date,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            do {
                // Map backend vaults to CoreData Safe entities
                var mappedSafes: [(address: String, name: String, chainId: String, version: String?)] = []
                
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
                    
                    // Validate address format
                    guard let _ = Address(vault.id) else {
                        VaultLogger.warning("Failed to parse vault \(index + 1): Invalid address format - \(vault.id)")
                        continue
                    }
                    
                    // Find Chain entity
                    guard let chain = Chain.by(vault.chainId) else {
                        VaultLogger.warning("Failed to parse vault \(index + 1): Chain not found for chainId \(vault.chainId)")
                        continue
                    }
                    
                    mappedSafes.append((
                        address: vault.id,
                        name: vault.name,
                        chainId: vault.chainId,
                        version: vault.contractVersion
                    ))
                    
                    VaultLogger.success("Mapped vault \(index + 1): \(vault.id.prefix(10))... -> Safe(\(vault.name), chain: \(vault.chainId))")
                }
                
                VaultLogger.info("Successfully mapped \(mappedSafes.count)/\(vaultResponses.count) vaults to Safe entities")
                
                if mappedSafes.count < vaultResponses.count {
                    let failed = vaultResponses.count - mappedSafes.count
                    VaultLogger.warning("\(failed) vault(s) failed to map and were skipped")
                }
                
                // Get count of existing safes (excluding demo) before deletion
                let existingSafes = try Safe.getAll()
                let existingSafesExcludingDemo = existingSafes.filter { $0.address != Safe.demoAddress }
                let deletedCount = existingSafesExcludingDemo.count
                
                // Destructive sync: clear all existing safes (except demo) and insert new ones
                VaultLogger.database("Clearing existing local safes...")
                
                // Delete all safes except demo
                for safe in existingSafesExcludingDemo {
                    Safe.remove(safe: safe)
                }
                
                VaultLogger.database("Deleted \(deletedCount) existing safe(s)")
                
                // Insert new safes
                VaultLogger.database("Inserting \(mappedSafes.count) new safe(s)...")
                
                for (index, mappedSafe) in mappedSafes.enumerated() {
                    guard let chain = Chain.by(mappedSafe.chainId) else {
                        VaultLogger.warning("Chain not found for \(mappedSafe.chainId), skipping safe")
                        continue
                    }
                    
                    // Determine if this safe should be selected
                    let shouldSelect = selectedSafeAddress == mappedSafe.address && selectedSafeChainId == mappedSafe.chainId
                    
                    let safe = Safe.create(
                        address: mappedSafe.address,
                        version: mappedSafe.version,
                        name: mappedSafe.name,
                        chain: chain,
                        selected: shouldSelect,
                        status: .deployed
                    )
                    
                    #if DEBUG
                    VaultLogger.debug("[\(index + 1)/\(mappedSafes.count)] Inserted: \(mappedSafe.address) (\(mappedSafe.name)) on chain \(mappedSafe.chainId)")
                    #else
                    VaultLogger.database("Inserted safe: \(mappedSafe.name) on chain \(mappedSafe.chainId)")
                    #endif
                }
                
                // If selected safe was removed, select first available safe
                if selectedSafeAddress != nil {
                    let newSafes = try Safe.getAll()
                    if !newSafes.contains(where: { $0.address == selectedSafeAddress && $0.chain?.id == selectedSafeChainId }) {
                        VaultLogger.info("Selected safe was removed, selecting first available safe")
                        if let firstSafe = newSafes.first {
                            firstSafe.select()
                        }
                    }
                } else if mappedSafes.isEmpty == false {
                    // If no safe was selected before and we have safes, select the first one
                    if let firstSafe = try Safe.getAll().first {
                        firstSafe.select()
                        VaultLogger.info("Selected first safe: \(firstSafe.address ?? "nil")")
                    }
                }
                
                let totalTime = Date().timeIntervalSince(startTime)
                VaultLogger.success("==================== SYNC COMPLETED ====================")
                VaultLogger.success("Total time: \(String(format: "%.0f", totalTime * 1000))ms")
                VaultLogger.success("Vaults synced: \(mappedSafes.count)")
                VaultLogger.success("Previous vaults: \(deletedCount)")
                VaultLogger.success("Net change: \(mappedSafes.count - deletedCount)")
                
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
}

