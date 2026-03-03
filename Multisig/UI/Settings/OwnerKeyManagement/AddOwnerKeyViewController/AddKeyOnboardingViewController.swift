//
//  AddKeyOnboardingViewController.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 04.08.21.
//  Copyright © 2021 Gnosis Ltd. All rights reserved.
//

import Foundation
import UIKit

// base class for onboarding screens when addding a key
class AddKeyOnboardingViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    struct Card {
        var image: UIImage?
        var title: String
        var body: String
        var link: Link?

        struct Link {
            var title: String
            var url: URL
        }
    }

    var cards: [Card] = []
    var tableView = UITableView()
    private let nextButton = UIButton(type: .system)
    var viewTrackingEvent: TrackingEvent!
    var createPasscodeFlow: CreatePasscodeFlow!

    // set by a controller during some step in the flow
    var keyParameters: AddKeyParameters?

    var completion: () -> Void = { }

    convenience init(cards: [Card], viewTrackingEvent: TrackingEvent, completion: @escaping () -> Void) {
        self.init()
        self.cards = cards
        self.completion = completion
        self.viewTrackingEvent = viewTrackingEvent
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .backgroundPrimary

        tableView.delegate = self
        tableView.dataSource = self
        tableView.registerCell(CardTableViewCell.self)
        tableView.backgroundColor = .backgroundPrimary
        tableView.separatorStyle = .none
        tableView.translatesAutoresizingMaskIntoConstraints = false

        nextButton.setText(NSLocalizedString("button_next", comment: "Next button title"), .filled)
        nextButton.addTarget(self, action: #selector(didTapNextButton(_:)), for: .touchUpInside)
        nextButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(tableView)
        view.addSubview(nextButton)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: nextButton.topAnchor, constant: -12),

            nextButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            nextButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            nextButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            nextButton.heightAnchor.constraint(equalToConstant: 56),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Tracker.trackEvent(viewTrackingEvent)
    }

    @objc func didTapNextButton(_ sender: Any) {
        completion()
    }

    // MARK: - Table view data source

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        cards.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueCell(CardTableViewCell.self, for: indexPath)
        let card = cards[indexPath.row]
        cell.set(image: card.image)
        cell.set(title: card.title)
        cell.set(body: card.body)
        cell.set(linkTitle: card.link?.title, url: card.link?.url)
        return cell
    }
}
