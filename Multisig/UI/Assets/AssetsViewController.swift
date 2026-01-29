//
//  AssetsViewController.swift
//  Multisig
//
//  Created by Vitaly Katz on 15.12.21.
//  Copyright © 2021 Gnosis Ltd. All rights reserved.
//

import UIKit

class AssetsViewController: ContainerViewController {

    // NOTE: `totalBalanceView` is intentionally non-private to allow subclasses (e.g. Invertir)
    // to override the primary actions without duplicating the entire controller.
    @IBOutlet weak var totalBalanceView: TotalBalanceView!
    @IBOutlet private weak var contentView: UIView!
    
    private var balances: [TokenBalance]?
    private var withdrawableBalances: [TokenBalance] = []

    private var safe: Safe?
    private let balancesViewController: BalancesViewController

    private var relayOnboardingFlow: RelayOnboardingFlow? = nil

    init(
        balancesViewController: BalancesViewController = BalancesViewController(),
        nibName: String = "AssetsViewController"
    ) {
        self.balancesViewController = balancesViewController
        // Use the nib to ensure outlets (totalBalanceView, contentView) are loaded.
        super.init(nibName: nibName, bundle: nil)
    }

    required init?(coder: NSCoder) {
        self.balancesViewController = BalancesViewController()
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        LogService.shared.debug("[AssetsContainer] viewDidLoad container=\(String(describing: type(of: self))) childBalancesVC=\(String(describing: type(of: balancesViewController)))")

        viewControllers = [balancesViewController]
        displayChild(at: 0, in: contentView)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(balanceLoading),
            name: .balanceLoading,
            object: nil)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateBalances),
            name: .balanceUpdated,
            object: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(selectedSafeChangedReceived),
            name: .selectedSafeChanged,
            object: nil)

        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(selectedSafeUpdatedReceived),
            name: .selectedSafeUpdated,
            object: nil)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(selectionChanged),
            name: .selectedSafeChanged,
            object: nil)
        
        totalBalanceView.onReceivedClicked = { [weak self] in
            let vc = ReceiveFundsViewController()
            let nav = ViewControllerFactory.modalWithRibbon(
                viewController: vc,
                storedChain: try? Safe.getSelected()?.chain
            )
            self?.present(nav, animated: true, completion: nil)
            Tracker.trackEvent(.assetTransferReceiveClicked)
        }
        
        totalBalanceView.onSendClicked = { [weak self] in
            //check if safe has an owner imported
            guard let safe = self?.safe else { return }
            if safe.isReadOnly {
                let vc = AddOwnerFirstViewController()
                vc.onSuccess = { [weak self, unowned safe] in
                    if !safe.isReadOnly {
                        self?.showSelectAssetsViewController()
                    }
                    self?.dismiss(animated: true)
                }
                let navigationController = UINavigationController(rootViewController: vc)
                self?.present(navigationController, animated: true)
            } else {
                self?.showSelectAssetsViewController()
            }
            Tracker.trackEvent(.assetTransferSendClicked)
        }

        totalBalanceView.onBuyClicked = { [weak self] in
            guard let safe = try? Safe.getSelected() else {
                return
            }
            Tracker.trackEvent(.userBuy)
            let vc = ViewControllerFactory.selectTopUpAddress(safe: safe)

            self?.present(vc, animated: true)
        }

        totalBalanceView.tokenBanner.onClaim = { [unowned self] in
            guard let safe = try? Safe.getSelected() else {
                return
            }

            Tracker.trackEvent(.bannerSafeTokenClaim)
            claimTokenFlow = ClaimSafeTokenFlow(safe: safe) { [unowned self] _ in
                claimTokenFlow = nil
            }
            present(flow: claimTokenFlow)
        }
        totalBalanceView.tokenBanner.onClose = { [unowned self] in
            safeTokenBannerWasShown = true
            totalBalanceView.tokenBanner.isHidden = !shouldShowSafeTokenBanner
            Tracker.trackEvent(.bannerSafeTokenSkip)
        }

        totalBalanceView.relayInfoBanner.onOpen = { [unowned self] in
            // open article in V1
            // Educational series will be shown in V2 of the relayer
            openInSafari(App.configuration.help.relayerInfoURL)
            Tracker.trackEvent(.bannerRelayOpen)
        }
        totalBalanceView.relayInfoBanner.onClose = { [unowned self] in
            relayBannerWasShown = true
            totalBalanceView.relayInfoBanner.isHidden = !shouldShowRelayBanner
            Tracker.trackEvent(.bannerRelaySkip)
        }

        safe = try? Safe.getSelected()

        updateSafeOptions()
    }

    private var shouldShowRelayBanner: Bool {
        relayBannerWasShown != true && (safe?.chain?.isSupported(feature: .relayingMobile) ?? false)
    }

    private var relayBannerWasShown: Bool? {
        get { AppSettings.relayBannerWasShown }
        set { AppSettings.relayBannerWasShown = newValue }
    }

    private var claimTokenFlow: ClaimSafeTokenFlow!
    private var transferSelectableAssets: [TransferSelectableAsset]?
    private var withdrawableTransferSelectableAssets: [TransferSelectableAsset] = []

    private var shouldShowSafeTokenBanner: Bool {
        // claim period has ended -> no need to show the banner
        return false
    }

    private var safeTokenBannerWasShown: Bool? {
        get { AppSettings.safeTokenBannerWasShown }
        set { AppSettings.safeTokenBannerWasShown = newValue }
    }

    private func showSelectAssetsViewController() {
        // Retirar picker should only show owned assets (balance > 0).
        if AppSettings.multiVaultBalancesEnabled {
            if !withdrawableTransferSelectableAssets.isEmpty {
                let selectAssetVC = SelectAssetViewController(transferAssets: withdrawableTransferSelectableAssets)
                let vc = ViewControllerFactory.modalWithRibbon(viewController: selectAssetVC)
                present(vc, animated: true)
                return
            }
            // Fallback: if transfer-selectable assets aren't available, use filtered balances.
        }

        guard !withdrawableBalances.isEmpty else { return }
        let selectAssetVC = SelectAssetViewController(
            balances: withdrawableBalances,
            chainId: safe?.chain?.id
        )
        let vc = ViewControllerFactory.modalWithRibbon(viewController: selectAssetVC)
        present(vc, animated: true)
        return
    }
    
    @objc private func balanceLoading() {
        totalBalanceView.loading = true
    }
    
    @objc private func updateBalances(_ notification: Notification) {
        totalBalanceView.loading = false
        let userInfo = notification.userInfo
        let total = userInfo?["total"] as? String
        totalBalanceView.amount = total
        self.balances = userInfo?["balances"] as? [TokenBalance]
        // Keep a shared "latest real balances" cache updated so other screens (e.g. Invertir markets)
        // can reuse real balances without reacting to zero-balance market lists.
        LatestBalancesCache.shared.update(balances: self.balances ?? [], allowAllZero: true)
        LatestBalancesCache.shared.updateTotalFiat(totalFiat: total, chainId: safe?.chain?.id)
        self.withdrawableBalances = (self.balances ?? []).filter { $0.balanceValue.value > 0 }
        if AppSettings.multiVaultBalancesEnabled {
            self.transferSelectableAssets = userInfo?["transferSelectableAssets"] as? [TransferSelectableAsset]
            self.withdrawableTransferSelectableAssets = (self.transferSelectableAssets ?? []).filter { $0.token.balanceValue.value > 0 }
        } else {
            self.transferSelectableAssets = nil
            self.withdrawableTransferSelectableAssets = []
        }
        // Disable Retirar if the user has no withdrawable assets (even if backend returned 0-balance rows).
        if AppSettings.multiVaultBalancesEnabled {
            // In some screens (e.g. Invertir markets) we intentionally publish real balances without
            // `transferSelectableAssets`. In that case, fall back to enabling the action if there are
            // any non-zero balances.
            totalBalanceView.sendEnabled = !withdrawableTransferSelectableAssets.isEmpty || !withdrawableBalances.isEmpty
        } else {
            totalBalanceView.sendEnabled = !withdrawableBalances.isEmpty
        }
    }
    
    @objc private func selectedSafeUpdatedReceived(notification: Notification) {
        self.safe = notification.object as? Safe
        updateSafeOptions()
    }

    @objc private func selectedSafeChangedReceived(notification: Notification) {
        self.safe = try? Safe.getSelected()
        updateSafeOptions()
    }

    private func updateSafeOptions() {
        totalBalanceView.tokenBanner.isHidden = !shouldShowSafeTokenBanner
        totalBalanceView.relayInfoBanner.isHidden = !shouldShowRelayBanner
        totalBalanceView.buyEnabled = safe?.chain?.isSupported(feature: .moonpay) ?? false
    }
    
    @objc private func selectionChanged(notification: Notification) {
        self.safe = try? Safe.getSelected()
    }
}
