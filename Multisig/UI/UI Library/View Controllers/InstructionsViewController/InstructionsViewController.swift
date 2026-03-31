//
//  InstructionsViewController.swift
//  Multisig
//
//  Created by Dirk Jäckel on 22.02.22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import UIKit

enum InstructionStepLeading {
    case number(String)
    case greenCheckmark
}

class InstructionsViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    @IBOutlet weak var button: UIButton!
    @IBOutlet weak var tableView: UITableView!

    /// Subclasses (e.g. safe onboarding “Comencemos”) can opt in to match login’s full-screen secondary surface.
    var prefersSecondaryScreenFill: Bool { false }

    enum Step {
        case header
        case step(leading: InstructionStepLeading, title: String, description: String)
        /// When `showsLeadingCheckmark` is false, only the title text is shown (full width).
        case finalStep(title: String, showsLeadingCheckmark: Bool = true)
    }

    var onClose: () -> Void = {}
    var onPrimaryAction: (() -> Void)?
    var steps: [Step] = []
    var chain: Chain?

    /// First-row header image (`InstructionHeaderTableViewCell`). Export/Import keep `launchscreen-logo` + non-circular.
    var instructionHeaderImageName: String = "launchscreen-logo"
    /// When true, header image is clipped to a circle (same diameter as Mobile Key “¿Es seguro?” hero).
    var instructionHeaderUsesCircularImage: Bool = false
    var instructionHeaderCircularDiameter: CGFloat = 141

    override func viewDidLoad() {
        super.viewDidLoad()

        if prefersSecondaryScreenFill {
            view.backgroundColor = .backgroundSecondary
            tableView.backgroundColor = .backgroundSecondary
            tableView.separatorStyle = .none
        }
        
        title = NSLocalizedString("ui_instructions_how_it_works_title", comment: "Title for the instructions screen")

        tableView.registerCell(InstructionHeaderTableViewCell.self)
        tableView.registerCell(FinalStepInstructionTableViewCell.self)
        tableView.registerCell(StepInstructionTableViewCell.self)

        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 120

        button.setText("OK, Let’s start", .filled)
    }
    
    override func closeModal() {
        onClose()
    }
    
    @IBAction func didTapButton(_ sender: Any) {
        if let onPrimaryAction = onPrimaryAction {
            onPrimaryAction()
            return
        }
        let createSafeVC = CreateSafeViewController()
        createSafeVC.onClose = onClose
        if let chain = chain {
            createSafeVC.chain = chain
        }
        
        show(createSafeVC, sender: self)
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let currentStep = steps[indexPath.row]
        switch currentStep {
        case .header:
            let cell = tableView.dequeueCell(InstructionHeaderTableViewCell.self, for: indexPath)
            cell.selectionStyle = .none
            cell.separatorInset.left = .greatestFiniteMagnitude
            cell.configure(
                imageName: instructionHeaderImageName,
                circularClip: instructionHeaderUsesCircularImage,
                circularDiameter: instructionHeaderCircularDiameter
            )
            return cell
        case let .step(leading: leading, title: title, description: description):
            let cell = tableView.dequeueCell(StepInstructionTableViewCell.self, for: indexPath)
            cell.selectionStyle = .none
            cell.separatorInset.left = .greatestFiniteMagnitude
            cell.apply(leading: leading)
            cell.headerLabel.text = title
            let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
            cell.descriptionLabel.text = trimmedDescription
            cell.descriptionLabel.isHidden = trimmedDescription.isEmpty
            let isLastRow = indexPath.row == steps.count - 1
            cell.setStyles(verticalBarViewHidden: isLastRow)
            return cell
        case let .finalStep(title: title, showsLeadingCheckmark: showsCheck):
            let cell = tableView.dequeueCell(FinalStepInstructionTableViewCell.self, for: indexPath)
            cell.configure(title: title, showsLeadingCheckmark: showsCheck)
            cell.selectionStyle = .none
            cell.separatorInset.left = .greatestFiniteMagnitude
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        steps.count
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard prefersSecondaryScreenFill else { return }
        cell.backgroundColor = .backgroundSecondary
        cell.contentView.backgroundColor = .backgroundSecondary
    }
}
