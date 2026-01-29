import UIKit

final class TangemCardKeyProvisioningCoordinator {
    typealias PresentIntro = (UIViewController) -> Void
    typealias PresentActivation = (UIViewController) -> Void
    typealias PresentPostActivationIntro = (UIViewController) -> Void
    typealias PresentImportFlow = (TangemKeyFlow) -> Void
    typealias ConfigureImportFlow = (TangemKeyFlow) -> Void
    typealias ImportCompletion = (Bool) -> Void

    private let presentIntro: PresentIntro
    private let presentActivation: PresentActivation
    private let presentPostActivationIntro: PresentPostActivationIntro
    private let presentImportFlow: PresentImportFlow
    private let configureImportFlow: ConfigureImportFlow
    private let onImportCompletion: ImportCompletion
    private let onActivationCancelled: (() -> Void)?
    private let importStartDelay: TimeInterval

    private var pendingImport = false

    init(presentIntro: @escaping PresentIntro,
         presentActivation: @escaping PresentActivation,
         presentPostActivationIntro: @escaping PresentPostActivationIntro,
         presentImportFlow: @escaping PresentImportFlow,
         configureImportFlow: @escaping ConfigureImportFlow,
         onImportCompletion: @escaping ImportCompletion,
         onActivationCancelled: (() -> Void)? = nil,
         importStartDelay: TimeInterval = 0.6) {
        self.presentIntro = presentIntro
        self.presentActivation = presentActivation
        self.presentPostActivationIntro = presentPostActivationIntro
        self.presentImportFlow = presentImportFlow
        self.configureImportFlow = configureImportFlow
        self.onImportCompletion = onImportCompletion
        self.onActivationCancelled = onActivationCancelled
        self.importStartDelay = importStartDelay
    }

    func start() {
        let introVC = buildIntroViewController { [weak self] in
            self?.showActivation()
        }
        presentIntro(introVC)
    }

    private func buildIntroViewController(onNext: @escaping () -> Void) -> AddKeyOnboardingViewController {
        let introVC = AddKeyOnboardingViewController()
        introVC.cards = [
            .init(
                image: UIImage(named: "ico-nfc"),
                title: NSLocalizedString("ui_tangem_card_key_tap_title", comment: "Title for tapping the Tangem Card Key"),
                body: NSLocalizedString("ui_tangem_card_key_intro_body", comment: "Intro body for Tangem card key activation")
            ),
            .init(
                image: UIImage(named: "ico-lock"),
                title: NSLocalizedString("ui_tangem_card_key_secure_title", comment: "Security title for Tangem card key activation"),
                body: NSLocalizedString("ui_tangem_card_key_secure_body", comment: "Security body for Tangem card key activation")
            )
        ]
        introVC.viewTrackingEvent = .tangemOwnerOnboarding
        introVC.navigationItem.title = NSLocalizedString("ui_tangem_activate_card_key_title", comment: "Title for the Tangem card key activation flow")
        introVC.navigationItem.largeTitleDisplayMode = .never
        introVC.completion = onNext
        return introVC
    }

    private func showActivation() {
        let activationVC = TangemActivationViewController(service: TangemService.shared)
        activationVC.autoStartActivation = true
        activationVC.shouldSuppressError = { [weak self] error in
            self?.isTangemWalletAlreadyCreated(error: error) ?? false
        }
        activationVC.onActivationResult = { [weak self] result in
            self?.handleActivationResult(result)
        }
        activationVC.onDidClose = { [weak self] in
            self?.handleActivationClosed()
        }
        presentActivation(activationVC)
    }

    private func handleActivationResult(_ result: Result<ActivatedCardInfo, Error>) {
        switch result {
        case .success:
            pendingImport = true
        case .failure(let error):
            pendingImport = isTangemWalletAlreadyCreated(error: error)
        }
    }

    private func handleActivationClosed() {
        if pendingImport {
            pendingImport = false
            let introVC = buildPostActivationIntroViewController { [weak self] in
                self?.startImportFlow()
            }
            presentPostActivationIntro(introVC)
        } else {
            onActivationCancelled?()
        }
    }

    private func startImportFlow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + importStartDelay) { [weak self] in
            guard let self else { return }
            let flow = TangemKeyFlow(service: TangemService.shared) { [weak self] success in
                self?.onImportCompletion(success)
            }
            self.configureImportFlow(flow)
            self.presentImportFlow(flow)
        }
    }

    private func isTangemWalletAlreadyCreated(error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("wallet") && (message.contains("already") || message.contains("exist"))
    }

    private func buildPostActivationIntroViewController(onNext: @escaping () -> Void) -> AddKeyOnboardingViewController {
        let introVC = AddKeyOnboardingViewController()
        introVC.cards = [
            .init(
                image: UIImage(named: "ico-nfc"),
                title: "",
                body: NSLocalizedString("ui_tangem_card_key_second_scan_body", comment: "Second scan instructions after Tangem activation")
            )
        ]
        introVC.viewTrackingEvent = .tangemOwnerOnboarding
        introVC.navigationItem.title = NSLocalizedString("ui_tangem_activate_card_key_title", comment: "Title for the Tangem card key activation flow")
        introVC.navigationItem.largeTitleDisplayMode = .never
        introVC.completion = onNext
        return introVC
    }

}
