//
//  InvertirFromTokenDetailFlowCoordinator.swift
//  Multisig
//
//  Created by Assistant on 05.01.26.
//

import UIKit
import SwiftCryptoTokenFormatter

struct InvertirDraft {
    let selectedToken: TokenBalance
    let investAmount: BigDecimal
    let estimatedFiat: Double
    let fiatCode: String
}

final class InvertirFromTokenDetailFlowCoordinator {
    private weak var navigationController: UINavigationController?
    private let token: TokenBalance

    var onFinish: (() -> Void)?

    init(navigationController: UINavigationController, token: TokenBalance) {
        self.navigationController = navigationController
        self.token = token
    }

    func start() {
        showEnterAmount()
    }

    private func showEnterAmount() {
        let fiatCode = AppSettings.selectedFiatCode
        let s1 = InvertirAmountViewController(tokenBalance: token, fiatCode: fiatCode)
        s1.onContinue = { [weak self] draft in
            self?.showConfirm(draft: draft)
        }
        navigationController?.pushViewController(s1, animated: true)
    }

    private func showConfirm(draft: InvertirDraft) {
        let s2 = InvertirConfirmViewController(draft: draft)
        s2.onConfirmInvestment = { [weak self] in
            self?.showInProgress()
        }
        navigationController?.pushViewController(s2, animated: true)
    }

    private func showInProgress() {
        let vc = InvertirInProgressViewController()
        vc.onFinish = { [weak self] in
            self?.navigationController?.popToRootViewController(animated: true)
            self?.onFinish?()
        }
        navigationController?.pushViewController(vc, animated: true)
    }
}


