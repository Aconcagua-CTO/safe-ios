//
//  VaultIconFadeView.swift
//  Multisig
//

import UIKit

final class VaultIconFadeView: UIView {
    private let iconImageView = UIImageView()
    private var fadeAnimation: UIViewPropertyAnimator?
    private let iconSize: CGFloat

    init(iconSize: CGFloat = 34) {
        self.iconSize = iconSize
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) {
        self.iconSize = 34
        super.init(coder: coder)
        setupUI()
    }

    deinit {
        stopAnimating()
    }

    func startAnimating() {
        stopAnimating()
        iconImageView.alpha = 1.0
        runFadeLoop()
    }

    func stopAnimating() {
        fadeAnimation?.stopAnimation(true)
        fadeAnimation?.finishAnimation(at: .current)
        fadeAnimation = nil
        iconImageView.alpha = 1.0
    }

    private func setupUI() {
        isUserInteractionEnabled = false
        backgroundColor = .clear

        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.tintColor = .labelPrimary
        let primaryIcon = UIImage(named: "tab-icon-balances")?.withRenderingMode(.alwaysTemplate)
        let fallbackIcon = UIImage(named: "safe-selector-not-selected-icon")?.withRenderingMode(.alwaysTemplate)
        iconImageView.image = primaryIcon ?? fallbackIcon

        addSubview(iconImageView)
        NSLayoutConstraint.activate([
            iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: iconSize),
        ])
    }

    private func runFadeLoop() {
        fadeAnimation = UIViewPropertyAnimator(duration: 1.5, curve: .easeInOut) { [weak self] in
            self?.iconImageView.alpha = 0.3
        }

        fadeAnimation?.addCompletion { [weak self] position in
            guard let self, position == .end else { return }
            self.iconImageView.alpha = 0.3
            let reverseAnimator = UIViewPropertyAnimator(duration: 1.5, curve: .easeInOut) {
                self.iconImageView.alpha = 1.0
            }
            self.fadeAnimation = reverseAnimator
            reverseAnimator.addCompletion { [weak self] reversePosition in
                guard reversePosition == .end else { return }
                self?.runFadeLoop()
            }
            reverseAnimator.startAnimation()
        }

        fadeAnimation?.startAnimation()
    }
}
