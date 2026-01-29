//
//  PostLoginGateIntroViewController.swift
//  Multisig
//
//  Created by GPT-5.2 Codex.
//

import UIKit

final class PostLoginGateIntroViewController: UIViewController {
    private let titleText: String
    private let detailText: String

    private var titleLabel: UILabel!
    private var detailLabel: UILabel!

    init(title: String, detail: String) {
        self.titleText = title
        self.detailText = detail
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        view.backgroundColor = .backgroundPrimary

        titleLabel = UILabel()
        titleLabel.text = titleText
        titleLabel.textAlignment = .center
        titleLabel.setStyle(.headline)
        titleLabel.textColor = .labelPrimary
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        detailLabel = UILabel()
        detailLabel.text = detailText
        detailLabel.textAlignment = .center
        detailLabel.setStyle(.body)
        detailLabel.textColor = .labelSecondary
        detailLabel.numberOfLines = 0
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(titleLabel)
        view.addSubview(detailLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            titleLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -32),

            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            detailLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            detailLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
    }
}
