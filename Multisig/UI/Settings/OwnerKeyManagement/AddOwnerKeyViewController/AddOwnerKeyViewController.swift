//
//  AddOwnerKeyViewController.swift
//  Multisig
//
//  Created by Andrey Scherbovich on 26.05.21.
//  Copyright © 2021 Gnosis Ltd. All rights reserved.
//

import UIKit


class AddOwnerKeyViewController: UITableViewController {
    private typealias SectionItems = (section: String, items: [Row])

    private var sections = [SectionItems]()

    var importKeyFlow: ImportKeyFlow!
    var generateKeyFlow: GenerateKeyFlow!
    var socialKeyFlow: AddSocialKeyFlow!
    private var cardKeyFlow: AddKeyFlow?
    private var tangemProvisioningCoordinator: TangemCardKeyProvisioningCoordinator?
    private var userProvisioningService: UserProvisioningService?
    private var isResolvingCardManufacturer = false

    enum Row {
        case social
        case generate
        case importKey
        case hardware
        case walletConnect
        case activateCard

        var title: String {
            switch self {
            case .social:
                return "Create or import with Google or Apple ID"
            case .generate:
                return "Crear nueva Mobile Key"
            case .importKey:
                return "Importar Mobile Key"
            case .hardware:
                return "Conectar una hardware wallet"
            case .walletConnect:
                return "Connect a key"
            case .activateCard:
                return "Activar nueva Card Key"
            }
        }

        var image: UIImage {
            switch self {
            case .generate:
                return UIImage(named: "ico-mobile")!
            case .importKey:
                return UIImage(named: "ico-key-type-key")!
            case .walletConnect:
                return UIImage(named: KeyType.walletConnect.imageName)!
            case .hardware:
                return UIImage(named: "ico-hardware-wallet")!
            case .social:
                return UIImage(named: "ico-add")!
            case .activateCard:
                return UIImage(named: "ico-nfc")!
            }
        }

        var style: AddOwnerKeyCell.Style {
            switch self {
            case .social:
                return .highlighted
            default:
                return .normal
            }
        }

        var detailsImage: UIImage? {
            switch self {
            case .walletConnect:
                return UIImage(named: "ico-wallet-logos")
            default:
                return nil
            }
        }
        
        var isHidden: Bool {
            switch self {
            case .walletConnect:
                return true
            default:
                return false
            }
        }
    }

    private(set) var completion: () -> Void = {}
    private var showsCloseButton: Bool = true

    convenience init(showsCloseButton: Bool = true, completion: @escaping () -> Void) {
        self.init()
        self.completion = completion
        self.showsCloseButton = showsCloseButton
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("ui_owner_keys_manage_title", comment: "Title for managing owner keys")
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.backBarButtonItem = UIBarButtonItem(title: "Back")
        
        ViewControllerFactory.removeNavigationBarBorder(self)

        if showsCloseButton {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .close,
                target: self,
                action: #selector(CloseModal.closeModal))
        }

        tableView.registerCell(AddOwnerKeyCell.self)
        tableView.registerHeaderFooterView(BasicHeaderView.self)
        tableView.separatorStyle = .none
        tableView.estimatedRowHeight = 90
        tableView.rowHeight = UITableView.automaticDimension
        tableView.backgroundColor = .backgroundSecondary
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }

        sections = [
            (section: "Start from scratch",
             items: AppConfiguration.FeatureToggles.socialLogin ? [.social, .generate] : [.generate]),

            (section: "Already have a key?", items: [.activateCard, .importKey, .hardware])
        ]

        tableView.tableHeaderView = nil
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Tracker.trackEvent(.ownerKeysOptions)
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].items.count
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueCell(AddOwnerKeyCell.self)
        let option = sections[indexPath.section].items[indexPath.row]

        cell.set(title: option.title)
        cell.set(image: option.image)
        cell.set(style: option.style)
        cell.set(detailsImage: option.detailsImage)
        
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch sections[indexPath.section].items[indexPath.row] {
        case .importKey:
            importKeyFlow = ImportKeyFlow { [weak self] _ in
                self?.importKeyFlow = nil
                self?.completion()
            }
            push(flow: importKeyFlow)
            return

        case .generate:
            generateKeyFlow = GenerateKeyFlow { [weak self] _ in
                self?.generateKeyFlow = nil
                self?.completion()
            }
            push(flow: generateKeyFlow)
            return

        case .hardware:
            let vc = ChooseHardwareWalletTableViewController()
            ViewControllerFactory.makeMultiLinesNavigationBar(vc)
            ViewControllerFactory.removeNavigationBarBorder(vc)

            vc.completion = completion

            show(vc, sender: self)
            
        case .activateCard:
            startCardKeyActivationFlow()
            
        case .social:
            socialKeyFlow = AddSocialKeyFlow { [weak self] _ in
                self?.socialKeyFlow = nil
                self?.completion()
            }
            push(flow: socialKeyFlow)
            return

        case .walletConnect:
            App.shared.snackbar.show(message: NSLocalizedString("ui_walletconnect_legacy_removed_message", comment: "Legacy WalletConnect-for-keys feature removed message"))
            return
        }
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 0
    }

    private func startTangemActivationFlow() {
        let coordinator = TangemCardKeyProvisioningCoordinator(
            presentIntro: { [weak self] introVC in
                guard let self else { return }
                self.show(introVC, sender: self)
            },
            presentActivation: { [weak self] activationVC in
                guard let self else { return }
                self.show(activationVC, sender: self)
            },
            presentPostActivationIntro: { [weak self] introVC in
                guard let self else { return }
                self.show(introVC, sender: self)
            },
            presentImportFlow: { [weak self] flow in
                guard let self else { return }
                self.cardKeyFlow = flow
                self.push(flow: flow)
            },
            configureImportFlow: { flow in
                // Keep a dedicated second scan after activation, matching post-login behavior.
                flow.skipIntro = true
                flow.skipWalletSelection = true
                // Settings activation should finish after importing the owner key.
                // Skip post-import delegate setup/signing screens to avoid entering a signing flow here.
                flow.skipPostImportFlow = true
            },
            onImportCompletion: { [weak self] _ in
                self?.cardKeyFlow = nil
                self?.tangemProvisioningCoordinator = nil
                self?.completion()
            },
            onActivationCancelled: { [weak self] in
                self?.tangemProvisioningCoordinator = nil
            }
        )
        tangemProvisioningCoordinator = coordinator
        coordinator.start()
    }

    private func startBurnerActivationFlow() {
        // Burner cards don't require a distinct "activation" step in-app today.
        // Proceed to connect/import the owner key via Burner scan.
        let flow = BurnerKeyFlow { [weak self] _ in
            self?.cardKeyFlow = nil
            self?.completion()
        }
        cardKeyFlow = flow
        push(flow: flow)
    }

    private func presentCardKeyManufacturerChoice() {
        let title = NSLocalizedString("ui_card_key_connect_title", comment: "Title for connecting a card key")
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: NSLocalizedString("ui_tangem_connect_card_title", comment: "Title for connecting a Tangem card"), style: .default) { [weak self] _ in
            self?.startTangemActivationFlow()
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("ui_burner_connect_card_title", comment: "Title for the burner owner key connect flow"), style: .default) { [weak self] _ in
            self?.startBurnerActivationFlow()
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("cancel", comment: "Cancel action title"), style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        present(alert, animated: true)
    }

    private func startCardKeyActivationFlow() {
        let cachedManufacturer = normalizedLeadManufacturer(AppSettings.leadCardManufacturer)
        guard App.shared.authRepository.isAuthenticated() else {
            routeCardKeyActivation(for: cachedManufacturer)
            return
        }

        guard !isResolvingCardManufacturer else { return }
        isResolvingCardManufacturer = true
        tableView.isUserInteractionEnabled = false
        LogService.shared.info("[AddOwnerKey] Resolving lead card manufacturer from backend")

        let service = UserProvisioningService(
            authRepository: App.shared.authRepository,
            logger: LogService.shared
        )
        userProvisioningService = service
        service.ensureUserRecord { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isResolvingCardManufacturer = false
                self.tableView.isUserInteractionEnabled = true
                self.userProvisioningService = nil

                switch result {
                case .success:
                    let refreshed = self.normalizedLeadManufacturer(AppSettings.leadCardManufacturer)
                    LogService.shared.info("[AddOwnerKey] Lead card manufacturer refreshed: \(refreshed)")
                    self.routeCardKeyActivation(for: refreshed)
                case .failure(let error):
                    LogService.shared.error("[AddOwnerKey] Failed to refresh lead card manufacturer", error: error)
                    self.routeCardKeyActivation(for: cachedManufacturer)
                }
            }
        }
    }

    private func routeCardKeyActivation(for manufacturer: String) {
        if manufacturer == "tangem" {
            startTangemActivationFlow()
        } else if manufacturer == "burner" {
            startBurnerActivationFlow()
        } else {
            presentCardKeyManufacturerChoice()
        }
    }

    private func normalizedLeadManufacturer(_ raw: String?) -> String {
        (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
