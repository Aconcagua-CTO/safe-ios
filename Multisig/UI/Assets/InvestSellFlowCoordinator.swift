//
//  InvestSellFlowCoordinator.swift
//  Multisig
//
//  Created by Assistant on 29.12.25.
//

import UIKit
import SwiftCryptoTokenFormatter

struct InvestSellDraft {
    let selectedToken: TokenBalance
    let sellAmount: BigDecimal
    let estimatedFiat: Double
    let fiatCode: String
}

final class InvestSellFlowCoordinator: NSObject, UIAdaptivePresentationControllerDelegate {
    private weak var presenter: UIViewController?
    private weak var navigationController: UINavigationController?

    var onDismiss: (() -> Void)?

    init(presenter: UIViewController) {
        self.presenter = presenter
    }

    func start() {
        let s1 = VenderSelectAssetViewController()
        s1.onTokenSelected = { [weak self] token in
            self?.showEnterAmount(selectedToken: token)
        }

        let nav = UINavigationController(rootViewController: s1)
        nav.modalPresentationStyle = .pageSheet
        if #unavailable(iOS 15) {
            nav.navigationBar.backgroundColor = .backgroundSecondary
        }
        nav.presentationController?.delegate = self
        presenter?.present(nav, animated: true)
        navigationController = nav
    }

    private func showEnterAmount(selectedToken: TokenBalance) {
        let fiatCode = AppSettings.selectedFiatCode
        let s2 = VenderAmountViewController(tokenBalance: selectedToken, fiatCode: fiatCode)
        s2.onContinue = { [weak self] draft in
            self?.showConfirm(draft: draft)
        }
        navigationController?.pushViewController(s2, animated: true)
    }

    private func showConfirm(draft: InvestSellDraft) {
        let s3 = VenderConfirmViewController(draft: draft)
        s3.onConfirmSell = { [weak self] in
            self?.showInProgress()
        }
        navigationController?.pushViewController(s3, animated: true)
    }

    private func showInProgress() {
        let vc = VenderInProgressViewController()
        vc.onFinish = { [weak self] in
            self?.navigationController?.dismiss(animated: true) { [weak self] in
                self?.onDismiss?()
            }
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        onDismiss?()
    }
}


