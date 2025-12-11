//
//  SafeBarView.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 21.10.20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import UIKit

/// When given:
///     - address, name: displays identicon, name, and address
///     - nothing: displays 'no safe loaded' icon and text
class SafeBarView: UINibView {
    @IBOutlet private weak var identiconView: UIImageView!
    @IBOutlet private weak var textLabel: UILabel!
    @IBOutlet private weak var detailLabel: UILabel!
    @IBOutlet private weak var button: UIButton!

    private(set) var prefix: String?
    private(set) var address: Address!
    private var isDetailOverridden = false
    private var displayName = "BOVEDA"
    
    override func commonInit() {
        super.commonInit()
        addTarget(self, action: #selector(didTouchDown(sender:forEvent:)), for: .touchDown)
        addTarget(self, action: #selector(didTouchUp(sender:forEvent:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(displayAddress),
                                               name: .chainSettingsChanged,
                                               object: nil)
        
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        textLabel.setStyle(.headline)
        textLabel.textAlignment = .left
        textLabel.numberOfLines = 1
        textLabel.lineBreakMode = .byTruncatingTail
        detailLabel.setStyle(.headlineSecondary)
        detailLabel.adjustsFontSizeToFitWidth = false
        detailLabel.minimumScaleFactor = 1.0
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.numberOfLines = 1
        detailLabel.textAlignment = .left
        updatePrimaryTexts()
        configureHistoryButton()
        setName("BOVEDA")
        LogService.shared.debug("[SafeBarView] awakeFromNib - screen bounds: \(UIScreen.main.bounds)")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        LogService.shared.debug("[SafeBarView] layoutSubviews - bounds: \(bounds), textLabel.frame: \(textLabel.frame), detailLabel.frame: \(detailLabel.frame), identiconView.frame: \(identiconView.frame)")
    }

    func setAddress(_ value: Address, prefix: String?) {
        self.address = value
        self.prefix = prefix
        isDetailOverridden = false
        setFixedLogoImage(grayscale: false)
        displayAddress()
    }

    func setAddress(_ value: Address, grayscale: Bool) {
        self.address = value
        isDetailOverridden = false
        setFixedLogoImage(grayscale: grayscale)
        displayAddress()
    }
    
    private func setFixedLogoImage(grayscale: Bool) {
        guard let logoImage = UIImage(named: "ico-safe-bar-logo") else {
            return
        }
        
        var processedImage = logoImage.circleShape() ?? logoImage
        
        if grayscale {
            processedImage = processedImage.grayscale() ?? processedImage
            identiconView.alpha = 0.3
        } else {
            identiconView.alpha = 1.0
        }
        
        identiconView.image = processedImage
    }

    func setDetail(text: String, style: GNOTextStyle = .bodyTertiary) {
        isDetailOverridden = true
        detailLabel.text = text
        detailLabel.setStyle(style)
        detailLabel.isHidden = false
        textLabel.numberOfLines = 1
        textLabel.text = displayName
    }

    func setName(_ value: String) {
        // Always display "BOVEDA" regardless of input
        displayName = "BOVEDA"
        updatePrimaryTexts()
    }


    private func configureHistoryButton() {
        let historyIcon = UIImage(named: "ico-history-transactions")
        button.setImage(historyIcon, for: .normal)
        button.tintColor = .labelPrimary
    }

    // encapsulating the button's target-action API
    func addTarget(_ target: Any?, action: Selector, for controlEvents: UIControl.Event) {
        button.addTarget(target, action: action, for: controlEvents)
    }

    func removeTarget(_ target: Any?, action: Selector?, for controlEvents: UIControl.Event) {
        button.removeTarget(target, action: action, for: controlEvents)
    }

    // visual reaction for user touches
    @objc private func didTouchDown(sender: UIButton, forEvent event: UIEvent) {
        alpha = 0.7
    }

    @objc private func didTouchUp(sender: UIButton, forEvent event: UIEvent) {
        alpha = 1.0
    }

    @objc func displayAddress() {
        guard !isDetailOverridden else { return }
        guard let address = address else { return }
        updatePrimaryTexts(with: address)
    }

    private func updatePrimaryTexts(with address: Address? = nil) {
        guard !isDetailOverridden else { return }
        textLabel.numberOfLines = 1
        textLabel.text = displayName
        let resolvedAddress = address ?? self.address
        detailLabel.isHidden = resolvedAddress == nil
        detailLabel.text = resolvedAddress?.ellipsized(prefix: 4, suffix: 4, checksummed: true)
        detailLabel.setStyle(.headlineSecondary)
        LogService.shared.debug("[SafeBarView] updatePrimaryTexts - text: \(displayName), detail: \(resolvedAddress?.ellipsized(prefix: 4, suffix: 4, checksummed: true) ?? "nil")")
    }
}

