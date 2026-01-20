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
            self?.createInvestTransactionRequest(draft: draft)
            self?.showInProgress()
        }
        navigationController?.pushViewController(s2, animated: true)
    }

    private func createInvestTransactionRequest(draft: InvertirDraft) {
        guard let selected = try? Safe.getSelected() else {
            LogService.shared.error("[TransactionRequests][invest] Missing selected Safe; cannot build vaultId")
            return
        }

        let vaultId = selected.addressValue.checksummed
        let amountString = TokenFormatter().string(from: draft.investAmount,
                                                   decimalSeparator: ".",
                                                   thousandSeparator: "")
        let dec = Decimal(string: amountString) ?? 0
        let tokenAmount = (dec as NSDecimalNumber).doubleValue

        let notes =
            "estimatedFiat=\(draft.estimatedFiat);" +
            " fiatCode=\(draft.fiatCode)"

        let payload = CreateTransactionRequestBody(
            transactionType: .invest,
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
        ) { result in
            switch result {
            case .success:
                LogService.shared.info("[TransactionRequests][invest] created")
            case .failure(let error):
                LogService.shared.error("[TransactionRequests][invest] create FAILED", error: error)
            }
        }
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


