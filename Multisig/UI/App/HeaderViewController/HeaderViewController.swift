//
//  HeaderViewController.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 21.10.20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import UIKit
import SwiftCryptoTokenFormatter

protocol HeaderSearchHandling: AnyObject {
    var headerSearchPlaceholder: String { get }
    func headerSearchDidChange(_ text: String)
}

/// Header bar will adapt to the devices size
final class HeaderViewController: ContainerViewController {
    @IBOutlet private weak var stackView: UIStackView!
    @IBOutlet private weak var headerBar: UIView!
    @IBOutlet private weak var barShadowView: UIImageView!
    @IBOutlet private weak var safeBarView: SafeBarView!
    @IBOutlet private weak var noSafeBarView: NoSafeBarView!
    @IBOutlet private weak var contentView: UIView!
    @IBOutlet private weak var headerBarHeightConstraint: NSLayoutConstraint!

    private var rootViewController: UIViewController?
    private var currentDataTask: URLSessionTask?
    private let searchController = UISearchController(searchResultsController: nil)

    var showsNavigationBar: Bool = false
    weak var searchHandler: HeaderSearchHandling?

    private var clientGatewayService: SafeClientGatewayService {
        guard let chain = try? Safe.getSelected()?.chain else {
            return App.shared.clientGatewayService
        }
        return chain.gatewayService()
    }
    var notificationCenter = NotificationCenter.default
    
    private var addSafeFlow: AddSafeFlow!
    private var claimTokenFlow: ClaimSafeTokenFlow!
    private var createSafeFlow: CreateSafeFlow!

    convenience init(rootViewController: UIViewController) {
        self.init(namedClass: nil)
        self.rootViewController = rootViewController
        viewControllers = [rootViewController]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        headerBar.backgroundColor = .backgroundSecondary
        safeBarView.addTarget(self, action: #selector(didTapSafeBarView(_:)), for: .touchUpInside)

        reloadHeaderBar()
        displayRootController()
        addObservers()
        headerBarHeightConstraint.constant = ScreenMetrics.safeHeaderHeight
        LogService.shared.debug("[HeaderViewController] viewDidLoad - screen bounds: \(UIScreen.main.bounds.size), isBigScreen: \(ScreenMetrics.isBigScreen), headerHeight: \(ScreenMetrics.safeHeaderHeight)")
        reloadSafeData()
        configureSearchIfNeeded()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        LogService.shared.debug("[HeaderViewController] viewDidLayoutSubviews - headerBar.frame: \(headerBar.frame), safeBarView.frame: \(safeBarView.frame)")
    }

    private func addObservers() {
        let updateNotifications: [NSNotification.Name] = [
            .selectedSafeChanged,
            .selectedSafeUpdated,
            .userProfileUpdated,
            .ownerKeyImported,
            .ownerKeyRemoved,
            .initiateTxNotificationReceived
        ]
        for name in updateNotifications {
            notificationCenter.addObserver(self,
                                           selector: #selector(didReceiveUpdateNotification(_:)),
                                           name: name,
                                           object: nil)
        }
        notificationCenter.addObserver(
            self,
            selector: #selector(reloadSafeData),
            name: UIScene.willEnterForegroundNotification,
            object: nil)
    }

    private func displayRootController() {
        assert(!viewControllers.isEmpty)
        displayChild(at: 0, in: contentView)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.isHidden = !showsNavigationBar
        configureSearchIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.navigationBar.isHidden = false
    }

    private func configureSearchIfNeeded() {
        guard let handler = searchHandler, showsNavigationBar else {
            navigationItem.searchController = nil
            return
        }

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = handler.headerSearchPlaceholder
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.searchBar.autocapitalizationType = .none

        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    private func addSafe() {
        addSafeFlow = AddSafeFlow(completion: { [weak self] _ in
            self?.addSafeFlow = nil
        })
        present(flow: addSafeFlow)
    }

    @objc private func didTapSafeBarView(_ sender: Any) {
        // Navigate to Transactions > History
        if let tabBarController = tabBarController as? MainTabBarViewController {
            tabBarController.openTransactions(segment: MainTabBarViewController.Path.queueSegment)
        }
    }

    @objc private func didReceiveUpdateNotification(_ notification: Notification) {
        if [.selectedSafeChanged, .initiateTxNotificationReceived].contains(notification.name) {
            reloadSafeData()
        }
        reloadHeaderBar()
    }

    @objc private func reloadHeaderBar() {
        do {
            let selectedSafe = try Safe.getSelected()
            let hasSafe = selectedSafe != nil
            safeBarView.isHidden = !hasSafe
            noSafeBarView.isHidden = hasSafe

            if let safe = selectedSafe {
                safeBarView.setName(currentUserFirstName())

                switch safe.safeStatus {
                case .deployed:
                    safeBarView.setAddress(safe.addressValue, prefix: safe.chain!.shortName)

                case .deploying, .indexing:
                    safeBarView.setAddress(safe.addressValue, grayscale: true)
                    safeBarView.setDetail(text: "Creating in progress...")

                case .deploymentFailed:
                    safeBarView.setAddress(safe.addressValue, grayscale: true)
                    safeBarView.setDetail(text: "Failed to create", style: .bodyError)
                }
            }
        } catch {
            App.shared.snackbar.show(
                error: GSError.error(description: NSLocalizedString("ui_safe_update_failed_error", comment: "Failed to update selected safe error"),
                                      error: error))
        }
    }

    @objc private func reloadSafeData() {
        currentDataTask?.cancel()
        do {
            guard let safe = try Safe.getSelected() else { return }

            currentDataTask = clientGatewayService.asyncSafeInfo(safeAddress: safe.addressValue,
                                                                 chainId: safe.chain!.id!) { [weak self] result in
                DispatchQueue.main.async { [weak self] in
                    switch result {
                    case .failure(let error):
                        // ignore cancellation error due to cancelling the
                        // currently running task.
                        if (error as NSError).code == URLError.cancelled.rawValue &&
                            (error as NSError).domain == NSURLErrorDomain {
                            return
                        }
                        LogService.shared.error("Failed to reload Safe Account info: \(error)")
                    case .success(let safeInfo):
                        safe.update(from: safeInfo)
                        self?.reloadHeaderBar()
                    }
                }
            }
        } catch {
            LogService.shared.error("Failed to reload Safe Account info: \(error)")
        }
    }

    private func currentUserFirstName() -> String? {
        guard let displayName = App.shared.authRepository.getCurrentUser()?.displayName else {
            return nil
        }

        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return trimmed.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
    }
}

// MARK: - UISearchResultsUpdating

extension HeaderViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let raw = searchController.searchBar.text ?? ""
        searchHandler?.headerSearchDidChange(raw)
    }
}
