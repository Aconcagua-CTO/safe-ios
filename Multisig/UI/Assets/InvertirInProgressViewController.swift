//
//  InvertirInProgressViewController.swift
//  Multisig
//
//  Created by Assistant on 05.01.26.
//

import UIKit

/// Screen 3 (Invertir): stage-1 execution stub.
final class InvertirInProgressViewController: UIViewController {
    var onFinish: (() -> Void)?

    private let titleLabel = UILabel()
    private let button = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = NSLocalizedString("ui_invertir_progress_title", comment: "Invertir progress title")

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setStyle(.title3)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center
        titleLabel.text = "Inversión en progreso"

        button.translatesAutoresizingMaskIntoConstraints = false
        button.setText(NSLocalizedString("ui_invertir_back_to_top_action", comment: "Invertir back to top action"), .filled)
        button.addTarget(self, action: #selector(didTapFinish), for: .touchUpInside)

        view.addSubview(titleLabel)
        view.addSubview(button)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -30),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            button.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            button.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            button.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    @objc private func didTapFinish() {
        onFinish?()
    }
}


