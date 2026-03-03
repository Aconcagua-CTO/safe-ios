import UIKit

enum TokenDetailFactory {
    static func makeViewController(token: TokenBalance, balancesProvider: TokenDetailBalancesProvider?) -> UIViewController? {
        PlaceholderTokenDetailViewController(token: token, balancesProvider: balancesProvider)
    }
}


