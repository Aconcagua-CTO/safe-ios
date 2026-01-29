//
//  ErrorViewController.swift
//  Multisig
//
//  Created by Dmitrii Bespalov on 06.06.24.
//  Copyright © 2024 Core Contributors GmbH. All rights reserved.
//

import UIKit

class ErrorViewController: UIViewController {
    
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var descriptionLabel: UILabel!
    @IBOutlet weak var textView: UITextView!
    @IBOutlet weak var button: UIButton!

    var titleText = NSLocalizedString("ui_data_operation_failed_title", comment: "Operation failed title")
    var bodyText = NSLocalizedString("ui_data_error_details_title", comment: "Error details title")
    var errorText = ""
    var buttonTitle = NSLocalizedString("button_done", comment: "Done button title")
    var imageName = "square.and.arrow.up.trianglebadge.exclamationmark"
    
    var completion: () -> Void = {}
    
    override func viewDidLoad() {
        super.viewDidLoad()
        imageView.image = UIImage(systemName: imageName)
        titleLabel.text = titleText
        descriptionLabel.text = bodyText
        textView.text = errorText
        button.setText(buttonTitle, .filled)
        
        titleLabel.setStyle(.headline)
        descriptionLabel.setStyle(.body)
        textView.setStyle(.bodyMedium)
    }
    
    @IBAction func done(_ sender: Any) {
        completion()
    }
    
}
