//
//  VenderInProgressViewController.swift
//  Multisig
//
//  Created by Assistant on 29.12.25.
//

import UIKit

/// Screen 4 (Vender): stage-1 execution stub.
final class VenderInProgressViewController: UIViewController {
    var onFinish: (() -> Void)?

    private let titleLabel = UILabel()
    private let button = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .backgroundPrimary
        title = "Vender"

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setStyle(.title3)
        titleLabel.textColor = .labelPrimary
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center
        titleLabel.text = "Venta en progreso"

        button.translatesAutoresizingMaskIntoConstraints = false
        button.setText("Volver a Invertir", .filled)
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


