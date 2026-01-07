//
//  TokenBalance.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 16.06.20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import Foundation
import SwiftCryptoTokenFormatter
import UIKit
import Solidity
import Ethereum

struct TokenBalance: Identifiable, Hashable {
    var id: String {
        address
    }
    var imageURL: URL?
    var image: UIImage?
    let address: String
    let name: String
    let symbol: String
    let category: String
    let balance: String
    let fiatValue: Double
    /// Fiat price per 1 token (as provided by backend when available).
    /// - Note: This is preferred for estimating fiat value of a user-entered amount,
    ///   because `fiatValue` may be incomplete in multi-chain aggregation scenarios
    ///   where some backends don't provide fiatBalance.
    let fiatConversion: Double
    let fiatBalance: String
    let balanceValue: BigDecimal
    let decimals: Int
}

extension TokenBalance {
    init(_ item: SCGBalance, code: String, chainId: String) {
        let whitelistEntry = TokenWhitelist.by(chainId: chainId, networkAddress: item.tokenInfo.address.address.checksummed)
        let category = whitelistEntry?.tokenCategory ?? "blackToken"
        let resolvedSymbol = whitelistEntry?.tokenSymbol ?? item.tokenInfo.symbol
        let resolvedName = whitelistEntry?.tokenName ?? item.tokenInfo.name
        self.init(address: item.tokenInfo.address.address,
                  name: resolvedName,
                  symbol: resolvedSymbol,
                  logoUri: item.tokenInfo.logoUri,
                  tokenBalance: item.balance,
                  decimals: item.tokenInfo.decimals,
                  fiatBalance: item.fiatBalance,
                  fiatConversion: item.fiatConversion,
                  code: code,
                  category: category)
    }

    init(address: Address,
         name: String?,
         symbol: String?,
         logoUri: String?,
         tokenBalance: UInt256String,
         decimals: UInt256String?,
         fiatBalance: String,
         fiatConversion: String = "0",
         code: String,
         category: String) {
        self.address = address.checksummed
        let coin = Chain.nativeCoin

        self.name = name ?? coin?.name ?? "Ether"
        self.symbol = symbol ?? coin?.symbol ?? "ETH"
        self.category = category
        self.imageURL = logoUri.flatMap { URL(string: $0) } ?? coin?.logoUrl

        let tokenFormatter = TokenFormatter()
        let amount = Int256(tokenBalance.value)
        let precision = decimals?.value ?? (coin?.decimals).map(UInt256.init(clamping:)) ?? 18

        self.decimals = Int(clamping: precision)
        self.balanceValue = BigDecimal(amount, self.decimals)
        self.balance = tokenFormatter.string(
            from: balanceValue,
            decimalSeparator: Locale.autoupdatingCurrent.decimalSeparator ?? ".",
            thousandSeparator: Locale.autoupdatingCurrent.groupingSeparator ?? ",")

        let fiatNumber = Self.serverCurrencyFormatter.number(from: fiatBalance) ?? 0
        self.fiatValue = fiatNumber.doubleValue
        self.fiatBalance = Self.displayCurrency(from: fiatBalance, code: code)

        let conversionNumber = Self.serverCurrencyFormatter.number(from: fiatConversion) ?? 0
        self.fiatConversion = conversionNumber.doubleValue
    }

    /// Creates a zero-balance token row from a whitelist entry (used for Markets screens).
    init(whitelist entry: TokenWhitelist, fiatCode: String = AppSettings.selectedFiatCode) {
        let rawAddress = (entry.networkAddress ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedAddress = rawAddress.isEmpty ? TokenBalance.nativeTokenAddress : rawAddress
        // IMPORTANT: Some backend addresses come in mixed-case but are not valid EIP-55 checksums.
        // Our `Address(stringLiteral:)` initializer uses `try!` internally and will crash on checksumWrong.
        // Normalize to lowercase (accepted), validate length/hex, and fall back to the zero address.
        let candidate = resolvedAddress.lowercased()
        let normalized: String = {
            let s = candidate.hasPrefix("0x") ? String(candidate.dropFirst(2)) : candidate
            let hex = CharacterSet(charactersIn: "0123456789abcdef")
            guard s.count == 40, s.unicodeScalars.allSatisfy({ hex.contains($0) }) else {
                return TokenBalance.nativeTokenAddress
            }
            return "0x" + s
        }()
        self.address = Address(stringLiteral: normalized).checksummed

        let resolvedSymbol = (entry.tokenSymbol ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.symbol = resolvedSymbol.isEmpty ? "—" : resolvedSymbol

        let resolvedName = (entry.tokenName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = resolvedName.isEmpty ? self.symbol : resolvedName

        let resolvedCategory = (entry.tokenCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.category = resolvedCategory.isEmpty ? "otros" : resolvedCategory

        if let image = entry.image, let url = URL(string: image) {
            self.imageURL = url
        } else {
            self.imageURL = nil
        }
        self.image = nil

        let d = Int(entry.decimals)
        self.decimals = d > 0 ? d : 18
        self.balanceValue = BigDecimal(Int256(0), self.decimals)
        self.balance = "0"

        self.fiatValue = 0
        self.fiatConversion = 0
        self.fiatBalance = Self.displayCurrency(from: "0", code: fiatCode)
    }

    static var serverCurrencyFormatter: NumberFormatter = {
        let currencyFormatter = NumberFormatter()
        // server always sends us number in en_US locale
        currencyFormatter.locale = Locale(identifier: "en_US")
        return currencyFormatter
    }()

    static func displayCurrency(from serverValue: String, code: String) -> String {
        // Always display fiat values with exactly 2 decimals across the app.
        // `serverValue` is expected to be an en_US formatted numeric string coming from backend.
        let trimmed = serverValue.trimmingCharacters(in: .whitespacesAndNewlines)

        // Prefer Decimal parsing to avoid Double rounding issues.
        let decimalValue: Decimal = {
            if let d = Decimal(string: trimmed, locale: Locale(identifier: "en_US")) {
                return d
            }
            let n = serverCurrencyFormatter.number(from: trimmed) ?? 0
            return n.decimalValue
        }()

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.autoupdatingCurrent
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.roundingMode = .halfUp

        let formatted = formatter.string(from: NSDecimalNumber(decimal: decimalValue)) ?? "0.00"
        return "\(formatted) \(code)"
    }

    var balanceWithSymbol: String {
        "\(balance) \(symbol)"
    }

    var fullBalanceWithSymbol: String {
        let value = Sol.UInt256(big: balanceValue.value.magnitude)
        let tokenAmount = Eth.TokenAmount(
                value: value,
                decimals: decimals)
        let fullBalance = tokenAmount.description
        return "\(fullBalance) \(symbol)"
    }

    static let nativeTokenAddress: String = Address.zero.checksummed

    /// Token amount formatted with up to 5 fraction digits (locale-aware).
    var balanceFormatted5: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.autoupdatingCurrent
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 5

        // Convert BigDecimal to a plain string (no grouping) before local formatting.
        let decimalString = TokenFormatter().string(
            from: balanceValue,
            decimalSeparator: ".",
            thousandSeparator: ""
        )
        if let number = Decimal(string: decimalString) {
            return formatter.string(from: number as NSDecimalNumber) ?? balance
        }
        return balance
    }
}
