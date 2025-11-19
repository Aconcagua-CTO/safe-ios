//
//  AddSafeTableViewCell.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 30.10.20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import UIKit

class AddSafeTableViewCell: UITableViewCell {
    @IBOutlet private weak var button: UIButton!
    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator: UIActivityIndicatorView
        if #available(iOS 13.0, *) {
            indicator = UIActivityIndicatorView(style: .medium)
        } else {
            indicator = UIActivityIndicatorView(style: .gray)
        }
        indicator.hidesWhenStopped = true
        indicator.color = UIColor(named: "primary")
        return indicator
    }()

    override func awakeFromNib() {
        super.awakeFromNib()
        button.titleLabel?.setStyle(.button)
        button.tintColor = UIColor(named: "primary")
        if #available(iOS 13.0, *) {
            button.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        }
    }
    
    func configureForRefresh(isRefreshing: Bool) {
        let title = isRefreshing ? "Refreshing vault list…" : "Refresh vault list"
        button.setTitle(title, for: .normal)
        button.alpha = isRefreshing ? 0.6 : 1.0
        
        if isRefreshing {
            if accessoryView !== activityIndicator {
                accessoryView = activityIndicator
            }
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
            accessoryView = nil
        }
    }
    
}
