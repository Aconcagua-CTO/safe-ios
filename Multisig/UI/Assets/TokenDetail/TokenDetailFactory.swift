import UIKit

enum TokenDetailFactory {
    static func makeViewController(token: TokenBalance, balancesProvider: TokenDetailBalancesProvider?) -> UIViewController? {
        // Route by the same section mapping used by balances lists.
        let normalized = token.category
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")

        switch normalized {
        case "stablecoin", "stablecoins", "savings", "cripto", "crypto":
            return SavingsTokenDetailViewController(token: token, balancesProvider: balancesProvider)
        case "moneymarket":
            return MoneyMarketTokenDetailViewController(token: token, balancesProvider: balancesProvider)
        default:
            // Other categories will get dedicated detail screens in later iterations.
            return PlaceholderTokenDetailViewController(token: token)
        }
    }
}


