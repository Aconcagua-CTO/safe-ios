import UIKit

final class PlaceholderTokenDetailViewController: UIViewController {
    private let token: TokenBalance

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
        label.text = "Token details coming soon."

        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}


