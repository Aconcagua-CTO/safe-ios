import UIKit

final class SavingsTokenDetailViewController: UIViewController {
    private let token: TokenBalance
    private weak var balancesProvider: TokenDetailBalancesProvider?

    private let tableView = UITableView(frame: .zero, style: .plain)
    private var rows: [NetworkTokenBalanceRow] = []

    private let invertirButton = UIButton(type: .system)
    private var invertirFlowCoordinator: InvertirFromTokenDetailFlowCoordinator?

    private let priceHeaderView = TokenPriceHistoryHeaderView()
    private let priceHistoryService = KrakenPriceHistoryService()
    private var ohlcTask: URLSessionDataTask?

    init(token: TokenBalance, balancesProvider: TokenDetailBalancesProvider?) {
        self.token = token
        self.balancesProvider = balancesProvider
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        ohlcTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .backgroundPrimary
        title = token.symbol

        configureTable()
        configureInvertirButton()
        configurePriceHistoryHeader()
        reloadRows()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // tableHeaderView uses frames (not Auto Layout). Keep it sized to current width.
        if tableView.tableHeaderView === priceHeaderView {
            let targetHeight: CGFloat = 220
            if priceHeaderView.frame.width != tableView.bounds.width || priceHeaderView.frame.height != targetHeight {
                priceHeaderView.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: targetHeight)
                tableView.tableHeaderView = priceHeaderView
            }
        }
    }

    private func configureTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .backgroundPrimary
        tableView.separatorColor = .separator
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }

        tableView.register(SavingsNetworkBalanceCell.self, forCellReuseIdentifier: SavingsNetworkBalanceCell.reuseIdentifier)
        tableView.dataSource = self
        tableView.delegate = self

        view.addSubview(tableView)
        view.addSubview(invertirButton)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: invertirButton.topAnchor, constant: -12),

            invertirButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            invertirButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            invertirButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            invertirButton.heightAnchor.constraint(equalToConstant: 56)
        ])
    }

    private func configureInvertirButton() {
        invertirButton.translatesAutoresizingMaskIntoConstraints = false
        invertirButton.setText("Invertir", .filled)
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

    private func configurePriceHistoryHeader() {
        // Always show a header. For non-Kraken tokens it will display "Chart coming soon".
        priceHeaderView.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 220)
        tableView.tableHeaderView = priceHeaderView

        guard let pair = balancesProvider?.krakenPair(for: token) else {
            priceHeaderView.showPlaceholder(text: "Chart coming soon")
            return
        }

        priceHeaderView.showLoading()
        ohlcTask = priceHistoryService.fetch1WeekClosePoints(pair: pair) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let servicePoints):
                    let points = servicePoints.map { TokenPriceHistoryHeaderView.Point(time: $0.time, value: $0.close) }
                    if points.count >= 2 {
                        self.priceHeaderView.showChart(points: points)
                    } else {
                        self.priceHeaderView.showPlaceholder(text: "Chart coming soon")
                    }
                case .failure:
                    self.priceHeaderView.showPlaceholder(text: "Chart coming soon")
                }
            }
        }
    }

    private func reloadRows() {
        rows = balancesProvider?.savingsBreakdownRows(for: token) ?? []
        tableView.reloadData()
    }
}

extension SavingsTokenDetailViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = rows[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: SavingsNetworkBalanceCell.reuseIdentifier, for: indexPath) as! SavingsNetworkBalanceCell
        cell.configure(row: row)
        return cell
    }
}

final class SavingsNetworkBalanceCell: UITableViewCell {
    static let reuseIdentifier = "SavingsNetworkBalanceCell"

    private let iconView = UIImageView()
    private let nameLabel = UILabel()
    private let amountLabel = UILabel()
    private let fiatLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.setStyle(.headlineSecondary)

        amountLabel.translatesAutoresizingMaskIntoConstraints = false
        amountLabel.setStyle(.headline)
        amountLabel.textAlignment = .right

        fiatLabel.translatesAutoresizingMaskIntoConstraints = false
        fiatLabel.setStyle(.footnoteSecondary)
        fiatLabel.textAlignment = .right

        let rightStack = UIStackView(arrangedSubviews: [amountLabel, fiatLabel])
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        rightStack.axis = .vertical
        rightStack.alignment = .trailing
        rightStack.spacing = 2

        let leftStack = UIStackView(arrangedSubviews: [iconView, nameLabel])
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        leftStack.axis = .horizontal
        leftStack.alignment = .center
        leftStack.spacing = 12

        let root = UIStackView(arrangedSubviews: [leftStack, UIView(), rightStack])
        root.translatesAutoresizingMaskIntoConstraints = false
        root.axis = .horizontal
        root.alignment = .center

        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),

            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
    }

    func configure(row: NetworkTokenBalanceRow) {
        nameLabel.text = row.networkName
        amountLabel.text = row.tokenAmountText
        fiatLabel.text = row.fiatText

        if let image = UIImage(named: "ico-chain-\(row.chainId)") {
            iconView.image = image
        } else {
            iconView.image = nil
        }
    }
}


