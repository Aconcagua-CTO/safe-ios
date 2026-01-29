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
class SafeBarView: UINibView, UIGestureRecognizerDelegate {
    @IBOutlet private weak var identiconView: UIImageView!
    @IBOutlet private weak var textLabel: UILabel!
    @IBOutlet private weak var detailLabel: UILabel!
    @IBOutlet private weak var button: UIButton!
    private weak var addressTapButton: UIButton?
    private weak var addressAreaTapRecognizer: UITapGestureRecognizer?

    private(set) var prefix: String?
    private(set) var address: Address!
    private var isDetailOverridden = false
    private var displayName = "BOVEDA"
    
#if DEBUG
    private var debugTapGestureRecognizer: UITapGestureRecognizer?

    private func debugLog(_ message: String) {
        // Ensure visibility even when LogService filters debug logs.
        LogService.shared.debug(message)
        print(message)
    }
#endif

    override func commonInit() {
        super.commonInit()
        addTarget(self, action: #selector(didTouchDown(sender:forEvent:)), for: .touchDown)
        addTarget(self, action: #selector(didTouchUp(sender:forEvent:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(displayAddress),
                                               name: .chainSettingsChanged,
                                               object: nil)

#if DEBUG
        // Debug-only tap recognizer to understand if touches reach this view at all.
        // (Does not cancel touches, so it shouldn't break existing behavior.)
        let gr = UITapGestureRecognizer(target: self, action: #selector(debugDidTapSafeBar(_:)))
        gr.cancelsTouchesInView = false
        addGestureRecognizer(gr)
        debugTapGestureRecognizer = gr
        debugLog("[SafeBarView][DEBUG] commonInit - added debug tap recognizer, isUserInteractionEnabled=\(isUserInteractionEnabled)")
#endif
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
        configureAddressTap()
        configureAddressAreaTap()
        updatePrimaryTexts()
        configureHistoryButton()
        setName(nil)
        LogService.shared.debug("[SafeBarView] awakeFromNib - screen bounds: \(UIScreen.main.bounds)")
#if DEBUG
        debugLog("[SafeBarView][DEBUG] awakeFromNib - detailLabel.userInteractionEnabled(xib)=\(detailLabel.isUserInteractionEnabled)")
#endif
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        LogService.shared.debug("[SafeBarView] layoutSubviews - bounds: \(bounds), textLabel.frame: \(textLabel.frame), detailLabel.frame: \(detailLabel.frame), identiconView.frame: \(identiconView.frame)")
#if DEBUG
        if let addressTapButton {
            debugLog("[SafeBarView][DEBUG] layoutSubviews - detailLabel.frame=\(detailLabel.frame), tapButton.frame=\(addressTapButton.frame), tapButton.isHidden=\(addressTapButton.isHidden), tapButton.isUserInteractionEnabled=\(addressTapButton.isUserInteractionEnabled)")
        } else {
            debugLog("[SafeBarView][DEBUG] layoutSubviews - tapButton is nil (configureAddressTap may not have run / container nil)")
        }
#endif
    }

    func setAddress(_ value: Address, prefix: String?) {
        self.address = value
        self.prefix = prefix
        isDetailOverridden = false
        setFixedLogoImage(grayscale: false)
        displayAddress()
#if DEBUG
        debugLog("[SafeBarView][DEBUG] setAddress(prefix:) - address=\(value.checksummed), prefix=\(prefix ?? "nil")")
#endif
    }

    func setAddress(_ value: Address, grayscale: Bool) {
        self.address = value
        isDetailOverridden = false
        setFixedLogoImage(grayscale: grayscale)
        displayAddress()
#if DEBUG
        debugLog("[SafeBarView][DEBUG] setAddress(grayscale:) - address=\(value.checksummed), grayscale=\(grayscale)")
#endif
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

    func setName(_ value: String?) {
        displayName = greeting(from: value)
        updatePrimaryTexts()
    }

    private func greeting(from name: String?) -> String {
        guard let rawName = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawName.isEmpty else {
            return "BOVEDA"
        }

        let firstComponent = rawName.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? rawName
        return "Hola, \(firstComponent)"
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
        detailLabel.text = resolvedAddress?.ellipsized()
        detailLabel.setStyle(.headlineSecondary)
        LogService.shared.debug("[SafeBarView] updatePrimaryTexts - text: \(displayName), detail: \(resolvedAddress?.ellipsized() ?? "nil")")
    }

    private func configureAddressTap() {
        // UILabel tap gesture recognizers can be flaky depending on view hierarchy.
        // Use a transparent UIButton pinned to the label to reliably receive touches.
        detailLabel.isUserInteractionEnabled = false

        // Avoid duplicating the overlay if `awakeFromNib` is called more than once.
        if addressTapButton != nil { return }
        guard let container = detailLabel.superview else { return }

        let tapButton = UIButton(type: .custom)
        tapButton.backgroundColor = .clear
        tapButton.accessibilityTraits = .button
        tapButton.accessibilityLabel = NSLocalizedString("ui_copied_to_clipboard_message", comment: "Copied to clipboard message")
        tapButton.accessibilityIdentifier = "safeBarView.addressTapButton"
        tapButton.addTarget(self, action: #selector(didTapAddressLabel), for: .touchUpInside)

        tapButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tapButton)
        NSLayoutConstraint.activate([
            tapButton.leadingAnchor.constraint(equalTo: detailLabel.leadingAnchor),
            tapButton.trailingAnchor.constraint(equalTo: detailLabel.trailingAnchor),
            tapButton.topAnchor.constraint(equalTo: detailLabel.topAnchor),
            tapButton.bottomAnchor.constraint(equalTo: detailLabel.bottomAnchor)
        ])
        addressTapButton = tapButton

#if DEBUG
        debugLog("[SafeBarView][DEBUG] configureAddressTap - created tapButton, container=\(type(of: container)), container.isUserInteractionEnabled=\(container.isUserInteractionEnabled)")
#endif
    }

    private func configureAddressAreaTap() {
        // Some view hierarchies (esp. involving stack views) can cause hit-testing to resolve
        // to a container instead of the intended subview. To make copy reliable, attach a tap
        // recognizer to the whole SafeBarView and only react when the tap lands inside the
        // address label's frame.
        if addressAreaTapRecognizer != nil { return }
        let gr = UITapGestureRecognizer(target: self, action: #selector(didTapAddressArea(_:)))
        gr.cancelsTouchesInView = false
        gr.delegate = self
        addGestureRecognizer(gr)
        addressAreaTapRecognizer = gr
#if DEBUG
        debugLog("[SafeBarView][DEBUG] configureAddressAreaTap - added address-area recognizer")
#endif
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Don't interfere with the history button.
        if touch.view?.isDescendant(of: button) == true { return false }
        return true
    }

    @objc private func didTapAddressLabel() {
        guard let address = address else { return }
        LogService.shared.debug("[SafeBarView] didTapAddressLabel - copying address")
#if DEBUG
        debugLog("[SafeBarView][DEBUG] didTapAddressLabel - fired, address=\(address.checksummed)")
#endif
        copyAddressToClipboard(address)
    }

#if DEBUG
    @objc private func didTapAddressArea(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let location = recognizer.location(in: self)
        let detailFrame = detailLabel.convert(detailLabel.bounds, to: self)
        let isInside = detailFrame.contains(location)
        debugLog("[SafeBarView][DEBUG] didTapAddressArea - location=\(location), detailFrame=\(detailFrame), isInside=\(isInside)")
        guard isInside, let address else { return }
        copyAddressToClipboard(address)
    }
#else
    @objc private func didTapAddressArea(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let location = recognizer.location(in: self)
        let detailFrame = detailLabel.convert(detailLabel.bounds, to: self)
        guard detailFrame.contains(location), let address else { return }
        copyAddressToClipboard(address)
    }
#endif

    private func copyAddressToClipboard(_ address: Address) {
        let prefixString = (AppSettings.copyAddressWithChainPrefix && prefix != nil) ? "\(prefix!):" : ""
        Pasteboard.string = prefixString + address.checksummed
        App.shared.snackbar.show(
            message: NSLocalizedString("ui_copied_to_clipboard_message", comment: "Copied to clipboard message"),
            duration: 2
        )
    }

#if DEBUG
    @objc private func debugDidTapSafeBar(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let location = recognizer.location(in: self)
        let hit = hitTest(location, with: nil)
        let locationInDetail = recognizer.location(in: detailLabel)
        let isInsideDetailBounds = detailLabel.bounds.contains(locationInDetail)
        let detailFrame = detailLabel.convert(detailLabel.bounds, to: self)
        debugLog("[SafeBarView][DEBUG] tap - location=\(location), hit=\(hit.map { String(describing: type(of: $0)) } ?? "nil"), isInsideDetailBounds=\(isInsideDetailBounds), detailFrame=\(detailFrame)")
    }
#endif
}

