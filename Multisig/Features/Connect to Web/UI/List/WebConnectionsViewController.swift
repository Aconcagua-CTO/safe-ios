//
//  PairedBrowsersViewController.swift
//  Multisig
//
//  Created by Andrey Scherbovich on 07.09.21.
//  Copyright © 2021 Gnosis Ltd. All rights reserved.
//

import UIKit
import WalletConnectSwift

class WebConnectionsViewController: UITableViewController, ExternalURLSource, WebConnectionListObserver {

    @IBOutlet private var infoButton: UIBarButtonItem!

    private weak var timer: Timer?

    private var connections = [WebConnection]()
    private var connectionController = WebConnectionController.shared

    private static let relativeDateTimerUpdateInterval: TimeInterval = 15
    private let warningSection = 0
    private let dataSection = 1

    var url: URL?

    override func viewDidLoad() {
        super.viewDidLoad()
        url = App.configuration.help.desktopPairingURL

        title = NSLocalizedString("ui_ctw_connect_to_web_title", comment: "Connect to web title")

        tableView.backgroundColor = .backgroundPrimary
        tableView.registerCell(WebConnectionTableViewCell.self)
        tableView.registerCell(WarningTableViewCell.self)
        tableView.registerHeaderFooterView(DesktopPairingHeaderView.self)
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 100

        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 100

        infoButton = UIBarButtonItem(image: UIImage(named: "ico-info-toolbar")?.withTintColor(.primary),
                style: UIBarButtonItem.Style.plain,
                target: self,
                action: #selector(openHelpUrl))
        navigationItem.rightBarButtonItem = infoButton

        subscribeToNotifications()

        update()

        startTimer()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Tracker.trackEvent(.webConnectionList)
        AppSettings.didShowDeprecateConnectToWeb = true
    }

    private func subscribeToNotifications() {
        connectionController.attach(observer: self)
    }

    @objc private func openHelpUrl() {
        openExternalURL()
        Tracker.trackEvent(.webConnectionListOpenedInfo)
    }

    @objc private func update() {
        connections = connectionController.connections()

        DispatchQueue.main.async { [unowned self] in
            self.tableView.reloadData()
        }
    }

    func didUpdateConnections() {
        update()
    }

    @objc func updateConnectionsTimeInfo() {
        tableView.reloadData()
    }

    private func scan() {
        let vc = QRCodeScannerViewController()
        
        let string = NSLocalizedString("ui_ctw_go_to_safe_web_instruction", comment: "Connect to web instruction") as NSString
        let textStyle = GNOTextStyle.calloutMedium.color(.white)
        let highlightStyle = GNOTextStyle.bodyMedium.color(.white)
        let label = NSMutableAttributedString(string: string as String, attributes: textStyle.attributes)
        label.setAttributes(highlightStyle.attributes, range: string.range(of: NSLocalizedString("safe_web_brand", comment: "Safe Web brand")))
        label.setAttributes(highlightStyle.attributes, range: string.range(of: NSLocalizedString("connect_wallet_action", comment: "Connect wallet action")))
        vc.attributedLabel = label

        vc.scannedValueValidator = { value in
            guard value.starts(with: "safe-wc:") else {
                return .failure(GSError.InvalidWalletConnectQRCode())
            }
            return .success(value)
        }
        vc.modalPresentationStyle = .overFullScreen
        vc.delegate = self
        vc.setup()
        present(vc, animated: true, completion: nil)

        Tracker.trackEvent(.webConnectionQRScanner)
    }

    // MARK: - Table view data source
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        2
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case warningSection:
            return 1
        case dataSection:
            return connections.count
        default:
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case warningSection:
            let cell = tableView.dequeueCell(WarningTableViewCell.self, for: indexPath)
            cell.set(
                title: NSLocalizedString("ui_ctw_deprecated_title", comment: "Connect to web deprecated title"),
                description: NSLocalizedString("ui_ctw_deprecated_description", comment: "Connect to web deprecated description"),
                backgroundColor: .warning)
            cell.backgroundConfiguration = .clear()
            return cell
        case dataSection:
            guard indexPath.row < connections.count else { return UITableViewCell() }
            let connection = connections[indexPath.row]
            let header = connection.remotePeer?.name ?? NSLocalizedString("ui_ctw_connection_title", comment: "Connection title")
            let peerIconUrl: URL? = connection.remotePeer?.icons.first
            let chainId = connection.chainId.map(String.init) ?? Chain.ChainID.ethereumMainnet
            let keyAddress: Address? = connection.accounts.first
            let keyName: String? = keyAddress.flatMap { NamingPolicy.name(for: $0, chainId: chainId).name }
            
            let cell = tableView.dequeueCell(WebConnectionTableViewCell.self, for: indexPath)
            cell.setImage(url: peerIconUrl, placeholder: UIImage(named: "connection-placeholder"))
            cell.setHeader(header)
            cell.setConnectionInfo(connection.remotePeer?.url.host)
            cell.setConnectionTimeInfo(connection.createdDate?.timeAgo())
            cell.setKey(keyName, address: keyAddress)
            return cell
        default:
            return UITableViewCell()
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        switch indexPath.section {
        case warningSection:
            openHelpUrl()
        case dataSection:
            let connection = connections[indexPath.row]
            let detailsVC = WebConnectionDetailsViewController()
            detailsVC.connection = connection
            let vc = ViewControllerFactory.modal(viewController: detailsVC)
            present(vc, animated: true)
        default:
            break
        }
    }

    // MARK: - Table view delegate

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        // we want the header view to appear at the top of the table, so we show it not in the data section but
        // in the warning section
        guard section == warningSection else { return nil }
        let view = tableView.dequeueHeaderFooterView(DesktopPairingHeaderView.self)
        view.onScan = { [unowned self] in
            self.scan()
        }
        return view
    }
    
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if section == warningSection {
            return UITableView.automaticDimension
        } else {
            return 0
        }
    }

    override func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section == dataSection else { return nil }
        let connection = connections[indexPath.row]
        let actions = [
            UIContextualAction(style: .destructive,
                               title: NSLocalizedString("ui_ctw_disconnect_action", comment: "Disconnect action")) {  [weak self] _, _, completion in
                guard let `self` = self else { return }
                let alertController = DisconnectionConfirmationController.create(connection: connection)
                if let popoverPresentationController = alertController.popoverPresentationController {
                    popoverPresentationController.sourceView = tableView.cellForRow(at: indexPath)
                }
                self.present(alertController, animated: true)
            }]
        return UISwipeActionsConfiguration(actions: actions)
    }

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            timeInterval: Self.relativeDateTimerUpdateInterval,
            target: self,
            selector: #selector(updateConnectionsTimeInfo),
            userInfo: nil,
            repeats: true)
    }

    func stopTimer() {
        timer?.invalidate()
    }

    deinit {
        stopTimer()
        connectionController.detach(observer: self)
    }

    fileprivate func connect(to code: String) {
        do {
            let connection = try WebConnectionController.shared.connect(to: code)
            let connectionVC = WebConnectionRequestViewController()
            connectionVC.connectionController = WebConnectionController.shared
            connectionVC.connection = connection
            connectionVC.onFinish = { [weak self] in
                self?.dismiss(animated: true)
            }
            let nav = UINavigationController(rootViewController: connectionVC)
            present(nav, animated: true)
        } catch {
            App.shared.snackbar.show(message: error.localizedDescription)
        }
    }
}

extension WebConnectionsViewController: QRCodeScannerViewControllerDelegate {
    func scannerViewControllerDidScan(_ code: String) {
        dismiss(animated: true) { [unowned self] in
            connect(to: code)
        }
    }

    func scannerViewControllerDidCancel() {
        dismiss(animated: true, completion: nil)
    }
}

extension WebConnectionsViewController: NavigationRouter {
    func routeFrom(from url: URL) -> NavigationRoute? {
        nil
    }
    
    func canNavigate(to route: NavigationRoute) -> Bool {
        route.path == NavigationRoute.connectToWeb().path
    }

    func navigate(to route: NavigationRoute) {
        if let code = route.info["code"] as? String {
            connect(to: code)
        }
    }
}

class DisconnectionConfirmationController: UIAlertController {
    static func create(connection: WebConnection) -> DisconnectionConfirmationController {
        let alertController = DisconnectionConfirmationController(
                title: nil,
                message: NSLocalizedString("ui_ctw_disconnect_safe_message", comment: "Disconnect safe message"),
                preferredStyle: .multiplatformActionSheet)
        let remove = UIAlertAction(title: NSLocalizedString("ui_ctw_disconnect_action", comment: "Disconnect action"),
                                   style: .destructive) { _ in
            Tracker.trackEvent(.webConnectionDisconnected)
            WebConnectionController.shared.userDidDisconnect(connection)
        }
        let cancel = UIAlertAction(title: NSLocalizedString("cancel", comment: "Cancel action title"),
                                   style: .cancel,
                                   handler: nil)
        alertController.addAction(remove)
        alertController.addAction(cancel)
        return alertController
    }

    static func create(key: KeyInfo) -> DisconnectionConfirmationController {
        let alertController = DisconnectionConfirmationController(
                title: nil,
                message: NSLocalizedString("ui_ctw_disconnect_owner_message", comment: "Disconnect owner message"),
                preferredStyle: .multiplatformActionSheet)
        let remove = UIAlertAction(title: NSLocalizedString("ui_ctw_disconnect_action", comment: "Disconnect action"),
                                   style: .destructive) { _ in
            Tracker.trackEvent(.disconnectInstalledWallet)
            WebConnectionController.shared.disconnectConnections(account: key.address)
            NotificationCenter.default.post(name: .ownerKeyUpdated, object: nil, userInfo: nil)
        }
        let cancel = UIAlertAction(title: NSLocalizedString("cancel", comment: "Cancel action title"),
                                   style: .cancel,
                                   handler: nil)
        alertController.addAction(remove)
        alertController.addAction(cancel)
        return alertController
    }
}
