//
//  TransferSelectableAsset.swift
//  Multisig
//
//  Created by Assistant on 22.12.25.
//

import Foundation
import UIKit

/// Represents a selectable asset row for the Retirar flow when multi-vault aggregation is enabled.
struct TransferSelectableAsset {
    /// Aggregated balance for the token on the specific chain (fiat primary, token secondary).
    let token: TokenBalance
    /// Chain identifier (e.g., "137" for Polygon).
    let chainId: String
    /// Human-friendly chain name (falls back to chainId if unknown).
    let chainName: String
    /// Badge background color (chain theme if available).
    let badgeBackgroundColor: UIColor?
    /// Badge text color (chain theme if available).
    let badgeTextColor: UIColor?
    /// Safe that will be auto-selected when the row is tapped.
    let preferredSafe: Safe
    /// The balance belonging to the preferredSafe for this token+chain.
    let preferredSafeToken: TokenBalance
}


