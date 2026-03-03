//
//  TokenCategory.swift
//  Multisig
//

import Foundation

struct TokenCategory {
    // Canonical section IDs used for UI grouping.
    static let sectionUSD = "usd"
    static let sectionMoneyMarket = "moneymarket"
    static let sectionAcciones = "acciones"
    static let sectionEtfIndices = "etf_indices"
    static let sectionEtfOtros = "etf_otros"
    static let sectionOro = "oro"
    static let sectionCripto = "cripto"
    static let sectionRootstock = "rootstock"
    static let sectionOtros = "otros"
    static let sectionBlackToken = "blacktoken"

    static func normalize(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    static func sectionId(for raw: String?) -> String {
        sectionId(forNormalized: normalize(raw))
    }

    static func sectionId(forNormalized normalized: String) -> String {
        switch normalized {
        case "usd":
            return sectionUSD
        case "savings", "stablecoin", "stablecoins":
            return sectionUSD
        case "moneymarket", "moneymarkettoken":
            return sectionMoneyMarket
        case "acciones":
            return sectionAcciones
        case "etfotros":
            return sectionEtfOtros
        case "etfdeindices":
            return sectionEtfIndices
        case "oro", "gold", "commodities":
            return sectionOro
        case "token", "cripto", "crypto":
            return sectionCripto
        case "rootstock":
            return sectionRootstock
        case "blacktoken":
            return sectionBlackToken
        case "nft", "debt":
            return sectionBlackToken
        case "invest":
            // Legacy bucket; keep for backward compatibility.
            return sectionAcciones
        default:
            return sectionBlackToken
        }
    }

    static func isSavings(_ raw: String?) -> Bool {
        let normalized = normalize(raw)
        return ["usd", "savings", "stablecoin", "stablecoins"].contains(normalized)
    }

    static func isMoneyMarket(_ raw: String?) -> Bool {
        let normalized = normalize(raw)
        return normalized == "moneymarket"
    }

    static func isInvestLike(_ raw: String?) -> Bool {
        let normalized = normalize(raw)
        return ["invest", "acciones", "etfotros", "etfdeindices"].contains(normalized)
    }

    static func isGoldLike(_ raw: String?) -> Bool {
        let normalized = normalize(raw)
        return ["oro", "gold", "commodities"].contains(normalized)
    }

    static func isCryptoLike(_ raw: String?) -> Bool {
        let normalized = normalize(raw)
        return ["cripto", "crypto", "token"].contains(normalized)
    }

    static func isAllowedInvestTarget(_ raw: String?) -> Bool {
        // Allowed categories for the *target* (what the user buys) in v1.
        if isMoneyMarket(raw) { return true }
        if isGoldLike(raw) { return true }
        if isCryptoLike(raw) { return true }
        if isInvestLike(raw) { return true }
        return false
    }

    static func isAllowedInvestSource(_ raw: String?) -> Bool {
        // Allowed categories for the *source* (what the user sells) in v1.
        return isAllowedInvestTarget(raw)
    }
}
