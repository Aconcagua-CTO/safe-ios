//
//  InvertirTotalBalanceView.swift
//  Multisig
//
//  Created by Assistant on 12/18/25.
//

import UIKit

/// Header used only in the Invertir tab. Uses the same layout as `TotalBalanceView`
/// but customizes the two primary actions (Comprar/Vender) and removes arrow icons.
final class InvertirTotalBalanceView: TotalBalanceView {
    /// `UINibView` auto-loads a nib with the same name as the class.
    /// We don't have `InvertirTotalBalanceView.xib`, so load the base `TotalBalanceView.xib`
    /// and then customize it in `awakeFromNib()`.
    override func commonInit() {
        loadFromNib(
            name: "TotalBalanceView",
            bundle: Bundle(for: TotalBalanceView.self),
            owner: self
        )
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        receiveButton.setText("+ Comprar", .filled)
        receiveButton.setImage(nil, for: .normal)
        receiveButton.titleEdgeInsets = .zero
        receiveButton.imageEdgeInsets = .zero

        sendButton.setText("- Vender", .filled)
        sendButton.setImage(nil, for: .normal)
        sendButton.titleEdgeInsets = .zero
        sendButton.imageEdgeInsets = .zero
    }
}


