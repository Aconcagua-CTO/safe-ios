import UIKit

final class PlaceholderTokenDetailViewController: UIViewController {
    private let token: TokenBalance
    private let invertirButton = UIButton(type: .system)
    private var invertirFlowCoordinator: InvertirFromTokenDetailFlowCoordinator?

    init(token: TokenBalance) {
        self.token = token
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .backgroundPrimary
        title = token.symbol

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setStyle(.body)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = NSLocalizedString("ui_token_details_coming_soon", comment: "Token details coming soon")

        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        if shouldShowInvertirButton {
            configureInvertirButton()
            view.addSubview(invertirButton)
            NSLayoutConstraint.activate([
                invertirButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                invertirButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
                invertirButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
                invertirButton.heightAnchor.constraint(equalToConstant: 56)
            ])
        }
    }

    private var shouldShowInvertirButton: Bool {
        let normalized = token.category
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        return normalized == "usd"
    }

    private func configureInvertirButton() {
        invertirButton.translatesAutoresizingMaskIntoConstraints = false
        invertirButton.setText(NSLocalizedString("ui_invertir_progress_title", comment: "Invertir button title"), .filled)
        invertirButton.addTarget(self, action: #selector(didTapInvertir), for: .touchUpInside)
    }

    @objc private func didTapInvertir() {
        guard let nav = navigationController else { return }
        let flow = InvertirFromTokenDetailFlowCoordinator(navigationController: nav, token: token)
        flow.onFinish = { [weak self] in
            self?.invertirFlowCoordinator = nil
        }
        invertirFlowCoordinator = flow
        flow.start()
    }
}


