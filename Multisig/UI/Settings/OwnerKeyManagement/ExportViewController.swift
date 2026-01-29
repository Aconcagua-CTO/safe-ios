//
//  ExportViewController.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 26.05.21.
//  Copyright © 2021 Gnosis Ltd. All rights reserved.
//

import UIKit

class ExportViewController: ContainerViewController {

    var privateKey: String = ""
    var seedPhrase: [String]?

    var segmentVC: SegmentViewController!

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = NSLocalizedString("ui_export_title", comment: "Title for exporting an owner key or seed phrase")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .done,
            target: self,
            action: #selector(didTapExport(_:)))

        if let seedPhrase = seedPhrase {
            // create seed phrase and private key inside segment view controller
            let seedPhraseVC = SeedPhraseViewController(nibName: nil, bundle: nil)
            seedPhraseVC.seedPhrase = seedPhrase

            let privateKeyVC = PrivateKeyViewController(nibName: nil, bundle: nil)
            privateKeyVC.showsHeader = false
            privateKeyVC.privateKey = privateKey

            segmentVC = SegmentViewController(namedClass: nil)
            segmentVC.segmentItems = [
                SegmentBarItem(image: UIImage(named: "ico-seed-phrase")!,
                               title: NSLocalizedString("ui_owner_seed_phrase_tab_title", comment: "Tab title for seed phrase")),
                SegmentBarItem(image: UIImage(named: "ico-private-key")!,
                               title: NSLocalizedString("ui_owner_private_key_tab_title", comment: "Tab title for private key"))
            ]
            segmentVC.viewControllers = [
                seedPhraseVC,
                privateKeyVC
            ]
            segmentVC.selectedIndex = 0

            viewControllers = [segmentVC]
            displayChild(at: 0, in: view)
        } else {
            // only create private key controller
            let privateKeyVC = PrivateKeyViewController(nibName: nil, bundle: nil)
            privateKeyVC.showsHeader = true
            privateKeyVC.privateKey = privateKey

            viewControllers = [privateKeyVC]
            displayChild(at: 0, in: view)
        }
    }

    @objc func didTapExport(_ sender: Any) {
        let vc = seedPhrase == nil ? viewControllers.first : segmentVC?.selectedViewController
        switch vc {
        case let vc as SeedPhraseViewController:
            export(vc.seedPhrase.joined(separator: " "))
        case let vc as PrivateKeyViewController:
            export(vc.privateKey)
        default:
            assertionFailure("Check that controller is set up and configured correctly")
        }
    }

    func export(_ value: String) {
        Tracker.trackEvent(.backupUserCopiedSeedPhrase)
        let vc = UIActivityViewController(activityItems: [value], applicationActivities: nil)
        present(vc, animated: true, completion: nil)
    }
}
