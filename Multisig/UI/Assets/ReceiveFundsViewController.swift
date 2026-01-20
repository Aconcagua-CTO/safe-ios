//
//  ReceiveFundsViewController.swift
//  Multisig
//
//  Created by Assistant on 01/14/26.
//

import UIKit
import SwiftUI

/// "Ingresar" screen: standard modal (like Retirar) that shows the Safe address to receive funds.
/// Uses the existing SwiftUI `SafeInfoView` content but presented in a consistent navigation modal.
final class ReceiveFundsViewController: UIViewController {
    private var hostingController: UIViewController?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .backgroundSecondary

        navigationItem.title = "Ingresar"
        // Subtitle directly under the title (consistent with other nav-modals).
        navigationItem.prompt = "Hacé una transferencia a la siguiente dirección"

        let swiftUIView = SafeInfoView()
            .environment(\.managedObjectContext, App.shared.coreDataStack.viewContext)

        let host = UIHostingController(rootView: swiftUIView)
        host.view.backgroundColor = .backgroundSecondary
        host.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)

        hostingController = host
    }
}

