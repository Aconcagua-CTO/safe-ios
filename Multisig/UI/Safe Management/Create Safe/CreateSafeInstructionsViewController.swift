//
//  CreateSafeInstructionsViewController.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 22.02.22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import UIKit

class CreateSafeInstructionsViewController: InstructionsViewController {

    override var prefersSecondaryScreenFill: Bool { true }

    private var savedStandardAppearance: UINavigationBarAppearance?
    private var savedScrollEdgeAppearance: UINavigationBarAppearance?
    private var savedCompactAppearance: UINavigationBarAppearance?
    private var savedCompactScrollEdgeAppearance: UINavigationBarAppearance?

    convenience init() {
        self.init(namedClass: InstructionsViewController.self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        instructionHeaderImageName = "ico-mobile-key-boveda-card"
        instructionHeaderUsesCircularImage = true
        instructionHeaderCircularDiameter = 141

        navigationItem.largeTitleDisplayMode = .never
        title = NSLocalizedString("ui_safe_how_it_works_title", comment: "Safe creation how it works title")
        let finalStepTitle = NSLocalizedString("ui_safe_final_step_title", comment: "Final step title")
#if DEBUG
        print("[CreateSafeInstructions] ui_safe_final_step_title=\(finalStepTitle)")
#endif

        steps = [
            .header,
            .step(leading: .greenCheckmark,
                  title: NSLocalizedString("ui_safe_step_choose_name_title", comment: "Choose name step title"),
                  description: NSLocalizedString("ui_safe_step_choose_name_description", comment: "Choose name step description")),
            .step(leading: .number("2"),
                  title: NSLocalizedString("ui_safe_step_add_owners_title", comment: "Add owners step title"),
                  description: NSLocalizedString("ui_safe_step_add_owners_description", comment: "Add owners step description")),
            .step(leading: .number("3"),
                  title: NSLocalizedString("ui_safe_step_pay_network_fee_title", comment: "Pay network fee step title"),
                  description: NSLocalizedString("ui_safe_step_pay_network_fee_description", comment: "Pay network fee step description")),
            .step(leading: .number("4"),
                  title: finalStepTitle,
                  description: "")
        ]

        button.setText(NSLocalizedString("ui_safe_ok_lets_start_button", comment: "OK let's start button"), .filled)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applySecondaryNavigationBarAppearance()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        restoreNavigationBarAppearance()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Tracker.trackEvent(.createSafeIntro)
    }

    /// Match navigation bar (and status-bar backdrop) to `backgroundSecondary` so the title area isn’t system black.
    private func applySecondaryNavigationBarAppearance() {
        guard let navBar = navigationController?.navigationBar else { return }
        if savedStandardAppearance == nil {
            savedStandardAppearance = navBar.standardAppearance.copy() as? UINavigationBarAppearance
            savedScrollEdgeAppearance = navBar.scrollEdgeAppearance?.copy() as? UINavigationBarAppearance
            savedCompactAppearance = navBar.compactAppearance?.copy() as? UINavigationBarAppearance
            if #available(iOS 15.0, *) {
                savedCompactScrollEdgeAppearance = navBar.compactScrollEdgeAppearance?.copy() as? UINavigationBarAppearance
            }
        }
        let appearance = Self.secondaryChromeNavigationBarAppearance()
        navBar.standardAppearance = appearance
        navBar.scrollEdgeAppearance = appearance
        navBar.compactAppearance = appearance
        if #available(iOS 15.0, *) {
            navBar.compactScrollEdgeAppearance = appearance
        }
    }

    private func restoreNavigationBarAppearance() {
        guard let navBar = navigationController?.navigationBar else { return }
        if let savedStandardAppearance {
            navBar.standardAppearance = savedStandardAppearance
        }
        navBar.scrollEdgeAppearance = savedScrollEdgeAppearance
        navBar.compactAppearance = savedCompactAppearance
        if #available(iOS 15.0, *) {
            navBar.compactScrollEdgeAppearance = savedCompactScrollEdgeAppearance
        }
    }

    private static func secondaryChromeNavigationBarAppearance() -> UINavigationBarAppearance {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .backgroundSecondary
        appearance.shadowColor = .clear
        let titleFont = UIFont.gnoFont(forTextStyle: .headline)
        appearance.titleTextAttributes = [
            .font: titleFont,
            .foregroundColor: UIColor.labelPrimary
        ]
        let largeFont = UIFont.gnoFont(forTextStyle: .largeTitle)
        appearance.largeTitleTextAttributes = [
            .font: largeFont,
            .foregroundColor: UIColor.labelPrimary
        ]
        return appearance
    }
}
