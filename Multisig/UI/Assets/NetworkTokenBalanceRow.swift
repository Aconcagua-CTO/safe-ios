import Foundation

struct NetworkTokenBalanceRow: Hashable {
    let chainId: String
    let networkName: String
    let tokenAmountText: String
    let fiatText: String
    let fiatValue: Double
}


