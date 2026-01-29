//
//  QRCodeShareViewController.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 24.03.22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import UIKit

class QRCodeShareViewController: UIViewController {
    @IBOutlet weak var qrCodeView: QRCodeView!
    @IBOutlet weak var shareButton: UIButton!
    @IBOutlet weak var saveButton: UIButton!

    var value: String = "" {
        didSet {
            qrCodeView.value = value
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        shareButton.setText(NSLocalizedString("ui_wallet_share_code", comment: "Share code button"), .plain)
        saveButton.setText(NSLocalizedString("ui_wallet_save_image", comment: "Save image button"), .plain)
        qrCodeView.showsBorder = false
        qrCodeView.imageSizeInPoints = 600
    }

    @IBAction func didTapShare(_ sender: Any) {
        let vc = UIActivityViewController(activityItems: [qrCodeView.value], applicationActivities: nil)
        vc.completionWithItemsHandler = { _, success, _, _ in
            if success {
                App.shared.snackbar.show(message: NSLocalizedString("ui_qr_code_shared_message", comment: "QR code shared message"))
            }
        }
        present(vc, animated: true, completion: nil)
    }

    @IBAction func didTapSave(_ sender: Any) {
        guard let image = qrCodeView.imageView.image else { return }
        let vc = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        vc.completionWithItemsHandler = { _, success, _, _ in
            if success {
                App.shared.snackbar.show(message: NSLocalizedString("ui_qr_code_saved_message", comment: "QR code saved message"))
            }
        }
        present(vc, animated: true, completion: nil)
    }
}
