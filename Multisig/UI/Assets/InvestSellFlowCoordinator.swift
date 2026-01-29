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
            self?.createSellTransactionRequest(draft: draft)
            self?.showInProgress()
        }
        navigationController?.pushViewController(s3, animated: true)
    }

    private func createSellTransactionRequest(draft: InvestSellDraft) {
        guard let selected = try? Safe.getSelected() else {
            LogService.shared.error("[TransactionRequests][sell] Missing selected Safe; cannot build vaultId")
            return
        }

        let vaultId = selected.addressValue.checksummed
        let amountString = TokenFormatter().string(from: draft.sellAmount,
                                                   decimalSeparator: ".",
                                                   thousandSeparator: "")
        let dec = Decimal(string: amountString) ?? 0
        let tokenAmount = (dec as NSDecimalNumber).doubleValue

        let notes =
            "estimatedFiat=\(draft.estimatedFiat);" +
            " fiatCode=\(draft.fiatCode)"

        let payload = CreateTransactionRequestBody(
            transactionType: .sell,
            currency: draft.selectedToken.symbol,
            amount: max(0, tokenAmount),
            requestStatus: .requested,
            destinationAddress: nil,
            notes: notes
        )

        let service = TransactionRequestsService(authRepository: App.shared.authRepository, logger: LogService.shared)
        service.createTransactionRequestForCurrentSession(
            vaultEvmAddress: vaultId,
            chainId: selected.chain?.id,
            payload: payload
        ) { [service] result in
            switch result {
            case .success:
                LogService.shared.info("[TransactionRequests][sell] created")
            case .failure(let error):
                LogService.shared.error("[TransactionRequests][sell] create FAILED", error: error)
            }
        }
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


