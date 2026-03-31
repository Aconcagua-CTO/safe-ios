//
//  InvertirFromTokenDetailFlowCoordinator.swift
//  Multisig
//
//  Created by Assistant on 05.01.26.
//

import UIKit

struct InvertirDraft {
    let selectedToken: TokenBalance
    let investAmountFiat: Double
    let estimatedTokenAmount: Double
    let availableUsdBalanceFiat: Double
    let fiatCode: String
}

final class InvertirFromTokenDetailFlowCoordinator {
    private weak var navigationController: UINavigationController?
    private let token: TokenBalance
    private let availableUsdBalanceFiat: Double?

    var onFinish: (() -> Void)?

    init(navigationController: UINavigationController,
         token: TokenBalance,
         availableUsdBalanceFiat: Double? = nil) {
        self.navigationController = navigationController
        self.token = token
        self.availableUsdBalanceFiat = availableUsdBalanceFiat
    }

    func start() {
        showEnterAmount()
    }

    private func showEnterAmount() {
        let fiatCode = AppSettings.selectedFiatCode
        let available = availableUsdBalanceFiat ?? max(0, token.fiatValue)
        let s1 = InvertirAmountViewController(tokenBalance: token,
                                              fiatCode: fiatCode,
                                              availableUsdBalanceFiat: available)
        s1.onContinue = { [weak self] draft in
            self?.showConfirm(draft: draft)
        }
        navigationController?.pushViewController(s1, animated: true)
    }

    private func showConfirm(draft: InvertirDraft) {
        let s2 = InvertirConfirmViewController(draft: draft)
        s2.onConfirmInvestment = { [weak self] in
            self?.createInvestTransactionRequest(draft: draft)
            self?.showSubmittedSuccess(draft: draft)
        }
        navigationController?.pushViewController(s2, animated: true)
    }

    private func createInvestTransactionRequest(draft: InvertirDraft) {
        guard let selected = try? Safe.getSelected() else {
            LogService.shared.error("[TransactionRequests][invest] Missing selected Safe; cannot build vaultId")
            return
        }

        let vaultId = selected.addressValue.checksummed
        let tokenAmount = draft.estimatedTokenAmount > 0
            ? draft.estimatedTokenAmount
            : draft.investAmountFiat

        let notes =
            "estimatedFiat=\(draft.investAmountFiat);" +
            " estimatedTokenAmount=\(draft.estimatedTokenAmount);" +
            " availableUsdBalanceFiat=\(draft.availableUsdBalanceFiat);" +
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

    private func showSubmittedSuccess(draft: InvertirDraft) {
        let amountUsd = formatFiatAmount(draft.investAmountFiat)
        let body = String(
            format: NSLocalizedString(
                "ui_invertir_invest_request_created_body_format",
                comment: "Invertir invest request created body"
            ),
            amountUsd
        )

        let successVC = SuccessViewController(
            titleText: NSLocalizedString("ui_vender_sell_request_created_title", comment: "Order created title"),
            bodyText: body,
            primaryAction: NSLocalizedString("button_done", comment: "Done button title"),
            secondaryAction: nil,
            trackingEvent: nil
        )
        successVC.onDone = { [weak self] _ in
            self?.navigationController?.popToRootViewController(animated: true)
            self?.onFinish?()
        }
        navigationController?.show(successVC, sender: self)
    }

    private func formatFiatAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.autoupdatingCurrent
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: max(0, value))) ?? String(format: "%.2f", value)
    }
}


