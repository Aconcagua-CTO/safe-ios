//
//  BalancesRequest.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 02.11.20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import Foundation

struct BalancesRequest: JSONRequest {
    private let safeAddress: String
    private let chainId: String
    private let fiat: String
    private let queryString: String?
    
    // Chains that must use Transaction Service style paths (no /v1/chains/{id} prefix)
    private static let txServiceStyleChains: Set<String> = [Chain.ChainID.rootstock]

    var httpMethod: String { "GET" }
    var query: String? { queryString }

    var urlPath: String {
        let path: String
        if Self.txServiceStyleChains.contains(chainId) {
            // Transaction Service style (matches backend usage for custom chains like Rootstock)
            // Rootstock gateway uses /balances without fiat in path, fiat conversion handled separately
            path = "/api/v1/safes/\(safeAddress)/balances"
            #if DEBUG
            LogService.shared.debug("[BalancesRequest] Using Transaction Service style path for chainId: \(chainId), path: \(path)")
            #endif
        } else {
            // Default Safe Client Gateway multi-chain path
            path = "/v1/chains/\(chainId)/safes/\(safeAddress)/balances/\(fiat)"
            #if DEBUG
            LogService.shared.debug("[BalancesRequest] Using multi-chain gateway path for chainId: \(chainId), path: \(path)")
            #endif
        }
        return path
    }

    typealias ResponseType = SafeBalanceSummary
}

extension BalancesRequest {
    init(_ safeAddress: Address, chainId: String) {
        self.init(safeAddress: safeAddress.checksummed,
                  chainId: chainId,
                  fiat: AppSettings.selectedFiatCode,
                  queryString: nil)
    }

    /// Internal convenience initializer that allows adding query params (e.g. to include custom/untrusted tokens).
    init(safeAddress: Address,
         chainId: String,
         fiat: String = AppSettings.selectedFiatCode,
         query: String? = nil) {
        self.init(safeAddress: safeAddress.checksummed,
                  chainId: chainId,
                  fiat: fiat,
                  queryString: query)
    }

    /// Use when you need untrusted/unpriced tokens as well (i.e. "custom tokens").
    init(_ safeAddress: Address,
         chainId: String,
         includeUntrusted: Bool,
         excludeSpam: Bool = true,
         fiatCode: String = AppSettings.selectedFiatCode) {
        let q = "trusted=\(includeUntrusted ? "false" : "true")&exclude_spam=\(excludeSpam ? "true" : "false")"
        self.init(safeAddress: safeAddress.checksummed,
                  chainId: chainId,
                  fiat: fiatCode,
                  queryString: q)
    }
}

struct SafeBalanceSummary: Decodable {
    var fiatTotal: String
    var items: [SCGBalance]
    
    // Custom decoder to handle both Safe Client Gateway format and Transaction Service format
    init(from decoder: Decoder) throws {
        // Try to decode as standard format first (object with fiatTotal and items)
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            #if DEBUG
            LogService.shared.debug("[SafeBalanceSummary] Decoding as standard Safe Client Gateway format")
            #endif
            self.fiatTotal = try container.decode(String.self, forKey: .fiatTotal)
            
            // Decode items array and log each balance structure
            var itemsContainer = try container.nestedUnkeyedContainer(forKey: .items)
            var balances: [SCGBalance] = []
            var itemIndex = 0
            while !itemsContainer.isAtEnd {
                let balance = try itemsContainer.decode(SCGBalance.self)
                balances.append(balance)
                #if DEBUG
                LogService.shared.debug("[SafeBalanceSummary] Item[\(itemIndex)] decoded - symbol: \(balance.tokenInfo.symbol ?? "nil"), address: \(balance.tokenInfo.address.address), fiatBalance: '\(balance.fiatBalance)', fiatConversion: '\(balance.fiatConversion)'")
                #endif
                itemIndex += 1
            }
            self.items = balances
        } else {
            // Transaction Service format: array of balance objects
            #if DEBUG
            LogService.shared.debug("[SafeBalanceSummary] Decoding as Transaction Service format (array)")
            #endif
            var arrayContainer = try decoder.unkeyedContainer()
            var balances: [SCGBalance] = []
            
            while !arrayContainer.isAtEnd {
                let balanceContainer = try arrayContainer.nestedContainer(keyedBy: TransactionServiceBalanceKeys.self)
                
                // Decode balance (required)
                // Transaction Service returns balance as decimal string (e.g., "2723770000000000")
                let balanceString = try balanceContainer.decode(String.self, forKey: .balance)
                guard let uint256Value = UInt256(balanceString) else {
                    throw DecodingError.dataCorruptedError(forKey: .balance, in: balanceContainer, debugDescription: "Invalid balance format: \(balanceString)")
                }
                let balanceValue = UInt256String(uint256Value)
                
                // Decode tokenAddress (can be null for native currency)
                let tokenAddressString = try? balanceContainer.decodeIfPresent(String.self, forKey: .tokenAddress)
                
                // Decode token info (can be null)
                let tokenInfo = try? balanceContainer.decodeIfPresent(TransactionServiceTokenInfo.self, forKey: .token)
                
                // Create TokenInfo
                let tokenInfoObj: TokenInfo
                if let addressString = tokenAddressString, let address = AddressString(addressString) {
                    // ERC20 token
                    tokenInfoObj = TokenInfo(
                        address: address,
                        name: tokenInfo?.name,
                        symbol: tokenInfo?.symbol,
                        decimals: tokenInfo?.decimals.map { UInt256String(UInt256($0)) },
                        logoUri: tokenInfo?.logoUri
                    )
                } else {
                    // Native currency (tokenAddress is null)
                    // Use zero address for native currency
                    tokenInfoObj = TokenInfo(
                        address: AddressString.zero,
                        name: "Rootstock Bitcoin",
                        symbol: "RBTC",
                        decimals: UInt256String(UInt256(18)),
                        logoUri: nil
                    )
                }
                
                // Transaction Service doesn't provide fiat values, set to "0"
                let balance = SCGBalance(
                    tokenInfo: tokenInfoObj,
                    balance: balanceValue,
                    fiatBalance: "0",
                    fiatConversion: "0"
                )
                balances.append(balance)
            }
            
            self.items = balances
            // Calculate fiatTotal as sum of fiatBalances (will be "0" for Transaction Service)
            let total = balances.reduce(0.0) { sum, balance in
                sum + (Double(balance.fiatBalance) ?? 0.0)
            }
            self.fiatTotal = String(total)
            #if DEBUG
            LogService.shared.debug("[SafeBalanceSummary] Decoded \(balances.count) balance(s) from Transaction Service format")
            #endif
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case fiatTotal
        case items
    }
    
    private enum TransactionServiceBalanceKeys: String, CodingKey {
        case tokenAddress
        case token
        case balance
    }
    
    private struct TransactionServiceTokenInfo: Decodable {
        var name: String?
        var symbol: String?
        var decimals: Int?
        var logoUri: String?
    }
}

struct SCGBalance: Decodable {
    var tokenInfo: TokenInfo
    var balance: UInt256String
    var fiatBalance: String
    var fiatConversion: String
    
    // Memberwise initializer for manual construction (e.g., Transaction Service format)
    init(tokenInfo: TokenInfo, balance: UInt256String, fiatBalance: String, fiatConversion: String) {
        self.tokenInfo = tokenInfo
        self.balance = balance
        self.fiatBalance = fiatBalance
        self.fiatConversion = fiatConversion
    }
    
    enum CodingKeys: String, CodingKey {
        case tokenInfo  // JSON field is "tokenInfo", matches property name
        case balance
        case fiatBalance
        case fiatConversion
        case fiatBalanceSnake = "fiat_balance"
        case fiatConversionSnake = "fiat_conversion"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        #if DEBUG
        // Log all available keys in the JSON to see what fields are actually present
        let allKeys = container.allKeys
        LogService.shared.debug("[SCGBalance] Available keys in JSON: \(allKeys.map { $0.stringValue }.joined(separator: ", "))")
        #endif
        
        // Decode tokenInfo - JSON field is "tokenInfo"
        self.tokenInfo = try container.decode(TokenInfo.self, forKey: .tokenInfo)
        self.balance = try container.decode(UInt256String.self, forKey: .balance)
        
        // Try to decode fiatBalance - check both camelCase and snake_case
        if let fiatBal = try? container.decode(String.self, forKey: .fiatBalance) {
            self.fiatBalance = fiatBal
        } else if let fiatBal = try? container.decode(String.self, forKey: .fiatBalanceSnake) {
            self.fiatBalance = fiatBal
        } else {
            #if DEBUG
            LogService.shared.debug("[SCGBalance] fiatBalance not found in JSON (tried 'fiatBalance' and 'fiat_balance'), using default '0'")
            #endif
            self.fiatBalance = "0"
        }
        
        // Try to decode fiatConversion - check both camelCase and snake_case
        if let fiatConv = try? container.decode(String.self, forKey: .fiatConversion) {
            self.fiatConversion = fiatConv
        } else if let fiatConv = try? container.decode(String.self, forKey: .fiatConversionSnake) {
            self.fiatConversion = fiatConv
        } else {
            #if DEBUG
            LogService.shared.debug("[SCGBalance] fiatConversion not found in JSON (tried 'fiatConversion' and 'fiat_conversion'), using default '0'")
            #endif
            self.fiatConversion = "0"
        }
        
        #if DEBUG
        LogService.shared.debug("[SCGBalance] Decoded - symbol: \(tokenInfo.symbol ?? "nil"), address: \(tokenInfo.address.address), fiatBalance: '\(fiatBalance)', fiatConversion: '\(fiatConversion)'")
        #endif
    }
}

extension SafeBalanceSummary {
    init(fiatTotal: String, items: [SCGBalance]) {
        self.fiatTotal = fiatTotal
        self.items = items
    }
}

protocol BalancesAPI {
    func asyncBalances(safeAddress: Address,
                       chainId: String,
                       query: String?,
                       completion: @escaping (Result<SafeBalanceSummary, Error>) -> Void) -> URLSessionTask?
}

extension SafeClientGatewayService: BalancesAPI {
    func asyncBalances(safeAddress: Address,
                       chainId: String,
                       query: String?,
                       completion: @escaping (Result<SafeBalanceSummary, Error>) -> Void) -> URLSessionTask? {
        asyncExecute(request: BalancesRequest(safeAddress: safeAddress,
                                             chainId: chainId,
                                             fiat: AppSettings.selectedFiatCode,
                                             query: query),
                     completion: completion)
    }
}

extension BalancesAPI {
    func asyncBalances(safeAddress: Address,
                       chainId: String,
                       completion: @escaping (Result<SafeBalanceSummary, Error>) -> Void) -> URLSessionTask? {
        asyncBalances(safeAddress: safeAddress,
                      chainId: chainId,
                      query: nil,
                      completion: completion)
    }
}
