import UIKit

enum TokenDetailFactory {
    static func makeViewController(token: TokenBalance, balancesProvider: TokenDetailBalancesProvider?) -> UIViewController? {
        let sectionId = TokenCategory.sectionId(for: token.category)
        if sectionId == TokenCategory.sectionUSD || TokenCategory.isCryptoLike(token.category) {
            return SavingsTokenDetailViewController(token: token, balancesProvider: balancesProvider)
        }
        if sectionId == TokenCategory.sectionMoneyMarket {
            return MoneyMarketTokenDetailViewController(token: token, balancesProvider: balancesProvider)
        }
        if sectionId == TokenCategory.sectionRootstock {
            return PlaceholderTokenDetailViewController(token: token)
        }
        // Other categories will get dedicated detail screens in later iterations.
        return PlaceholderTokenDetailViewController(token: token)
    }
}


