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

    func startWithToken(_ token: TokenBalance) {
        let fiatCode = AppSettings.selectedFiatCode
        let s2 = VenderAmountViewController(tokenBalance: token, fiatCode: fiatCode)
        s2.onContinue = { [weak self] draft in
            self?.showConfirm(draft: draft)
        }

        let nav = UINavigationController(rootViewController: s2)
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
            self?.showSubmittedSuccess(draft: draft)
        }
        navigationController?.pushViewController(s3, animated: true)
    }

    private func createSellTransactionRequest(draft: InvestSellDraft) {
        guard let selected = try? Safe.getSelected() else {
            LogService.shared.error("[TransactionRequests][sell] Missing selected Safe; cannot build vaultId")
            return
        }

        let vaultEvmAddress = selected.addressValue.checksummed
        let tokenChainId = draft.selectedToken.chainId ?? selected.chain?.id

        let amountString = TokenFormatter().string(from: draft.sellAmount,
                                                   decimalSeparator: ".",
                                                   thousandSeparator: "")
        let dec = Decimal(string: amountString) ?? 0
        let tokenAmount = (dec as NSDecimalNumber).doubleValue

        let notes =
            "estimatedFiat=\(draft.estimatedFiat);" +
            " fiatCode=\(draft.fiatCode)"

        let rawSymbol = draft.selectedToken.tokenSymbol ?? draft.selectedToken.symbol
        LogService.shared.debug("[TransactionRequests][sell] tokenChainId=\(tokenChainId ?? "nil") rawSymbol=\(rawSymbol) displaySymbol=\(draft.selectedToken.symbol) evm=\(vaultEvmAddress)")

        let payload = CreateTransactionRequestBody(
            transactionType: .sell,
            currency: rawSymbol,
            amount: max(0, tokenAmount),
            requestStatus: .requested,
            destinationAddress: nil,
            notes: notes
        )

        let service = TransactionRequestsService(authRepository: App.shared.authRepository, logger: LogService.shared)
        service.createTransactionRequestForCurrentSession(
            vaultEvmAddress: vaultEvmAddress,
            chainId: tokenChainId,
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

    private func showSubmittedSuccess(draft: InvestSellDraft) {
        let qty = formatNumber5(decimalDoubleValue(from: draft.sellAmount))
        let symbolUpper = draft.selectedToken.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let body = String(
            format: NSLocalizedString(
                "ui_vender_sell_request_created_body_format",
                comment: "Vender sell request created body"
            ),
            qty,
            symbolUpper
        )

        let successVC = SuccessViewController(
            titleText: NSLocalizedString("ui_vender_sell_request_created_title", comment: "Vender sell request created title"),
            bodyText: body,
            primaryAction: NSLocalizedString("button_done", comment: "Done button title"),
            secondaryAction: nil,
            trackingEvent: nil
        )
        successVC.onDone = { [weak self] _ in
            self?.navigationController?.dismiss(animated: true) { [weak self] in
                self?.onDismiss?()
            }
        }
        navigationController?.show(successVC, sender: self)
    }

    private func decimalDoubleValue(from value: BigDecimal) -> Double {
        let decimalString = TokenFormatter().string(from: value,
                                                    decimalSeparator: ".",
                                                    thousandSeparator: "")
        guard let dec = Decimal(string: decimalString) else { return 0 }
        return (dec as NSDecimalNumber).doubleValue
    }

    private func formatNumber5(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.autoupdatingCurrent
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 5
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.5f", value)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        onDismiss?()
    }
}


