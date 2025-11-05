//
//  VaultsService.swift
//  Multisig
//
//  Created on [Date]
//  Copyright © [Year] Gnosis Ltd. All rights reserved.
//

import Foundation

/**
 * Service for fetching vaults from Aconcagua backend
 */
class VaultsService {
    
    private let client: AuthenticatedHTTPClient
    private let decoder: JSONDecoder
    
    init(authRepository: AuthRepository, logger: Logger? = nil) {
        self.client = AuthenticatedHTTPClient(
            baseURL: ApiConfig.vaultsApiURL,
            authRepository: authRepository,
            logger: logger
        )
        self.decoder = JSONDecoder()
        // Configure decoder with date decoding strategy if needed
        decoder.dateDecodingStrategy = .iso8601
    }
    
    /**
     * Fetch vaults for a specific user
     * 
     * - Parameters:
     *   - userId: Firebase UID of the user
     *   - limit: Optional pagination limit
     *   - offset: Optional pagination offset
     *   - completion: Completion handler with Result containing VaultsListResponse or Error
     */
    func getVaultsByUser(
        userId: String,
        limit: Int? = nil,
        offset: Int? = nil,
        completion: @escaping (Result<VaultsListResponse, Error>) -> Void
    ) {
        VaultLogger.network("Fetching vaults for user: \(userId)")
        
        let request = VaultsApiRequest(userId: userId, limit: limit, offset: offset)
        
        _ = client.asyncExecute(request: request) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let data):
                VaultLogger.network("Received vaults response, parsing JSON...")
                do {
                    let response = try self.decoder.decode(VaultsListResponse.self, from: data)
                    VaultLogger.success("Successfully parsed \(response.items.count) vault(s)")
                    completion(.success(response))
                } catch {
                    VaultLogger.error("Failed to parse vaults response", error: error)
                    completion(.failure(error))
                }
                
            case .failure(let error):
                VaultLogger.error("Failed to fetch vaults", error: error)
                completion(.failure(error))
            }
        }
    }
}

