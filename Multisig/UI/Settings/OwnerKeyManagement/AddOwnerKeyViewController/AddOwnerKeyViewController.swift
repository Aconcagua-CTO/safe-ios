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
    var walletConnectKeyFlow: WalletConnectKeyFlow!
    var socialKeyFlow: AddSocialKeyFlow!

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
                return "Crear nueva Card Key"
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
                return UIImage(named: KeyType.deviceImported.imageName)!
            case .walletConnect:
                return UIImage(named: KeyType.walletConnect.imageName)!
            case .hardware:
                return UIImage(named: "ico-hardware-wallet")!
            case .social:
                return UIImage(named: "ico-add")!
            case .activateCard:
                return UIImage(named: "ico-payment-key")!
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

        title = "Add Owner Key"
        navigationItem.largeTitleDisplayMode = .always
        navigationController?.navigationBar.prefersLargeTitles = true
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
        let view = tableView.dequeueHeaderFooterView(BasicHeaderView.self)
        view.setName(sections[section].section, backgroundColor: .clear)

        return view
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

        case .walletConnect:
            walletConnectKeyFlow = WalletConnectKeyFlow { [weak self] _ in
                self?.walletConnectKeyFlow = nil
                self?.completion()
            }
            push(flow: walletConnectKeyFlow)
            return

        case .hardware:
            let vc = ChooseHardwareWalletTableViewController()
            ViewControllerFactory.makeMultiLinesNavigationBar(vc)
            ViewControllerFactory.removeNavigationBarBorder(vc)

            vc.completion = completion

            show(vc, sender: self)
            
        case .activateCard:
            let vc = ComingSoonViewController()
            vc.title = "Activar nueva Card Key"
            show(vc, sender: self)
            
        case .social:
            socialKeyFlow = AddSocialKeyFlow { [weak self] _ in
                self?.socialKeyFlow = nil
                self?.completion()
            }
            push(flow: socialKeyFlow)
            return
        }
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        BasicHeaderView.headerHeight
    }
}
