//
//  OnboardingViewController.swift
//  Multisig
//
//  Created by Moaaz on 6/7/22.
//  Copyright © 2022 Gnosis Ltd. All rights reserved.
//

import UIKit

class OnboardingViewController: UIViewController {

    @IBOutlet private weak var loadSafeButton: UIButton!
    @IBOutlet private weak var createSafeButton: UIButton!
    @IBOutlet private weak var demoButton: UIButton!
    @IBOutlet private weak var completelyNewLabel: UILabel!
    @IBOutlet private weak var skipButton: UIButton!
    @IBOutlet private weak var closeButton: UIButton!
    @IBOutlet private weak var actionsContainerView: UIStackView!
    @IBOutlet private weak var pageControl: UIPageControl!
    @IBOutlet private weak var collectionView: UICollectionView!
    
    private var createSafeFlow: CreateSafeFlow!
    private var addSafeFlow: AddSafeFlow!
    
    private let steps: [OnboardingStep] = [
        OnboardingStep(
            title: (
                text: NSLocalizedString("ui_onboarding_1_title", comment: "Onboarding screen 1 title"),
                highlightedText: NSLocalizedString("ui_onboarding_1_title_highlight", comment: "Onboarding screen 1 title highlight")
            ),
            description: (
                text: NSLocalizedString("ui_onboarding_1_body", comment: "Onboarding screen 1 body"),
                highlightedText: nil
            ),
            image: UIImage(named: "ico-onboarding-1")!,
            trackingEvent: .screenOnboarding1
        ),
        OnboardingStep(
            title: (
                text: NSLocalizedString("ui_onboarding_2_title", comment: "Onboarding screen 2 title"),
                highlightedText: NSLocalizedString("ui_onboarding_2_title_highlight", comment: "Onboarding screen 2 title highlight")
            ),
            description: (
                text: NSLocalizedString("ui_onboarding_2_body", comment: "Onboarding screen 2 body"),
                highlightedText: nil
            ),
            image: UIImage(named: "ico-onboarding-2")!,
            trackingEvent: .screenOnboarding2
        ),
        OnboardingStep(
            title: (
                text: NSLocalizedString("ui_onboarding_3_title", comment: "Onboarding screen 3 title"),
                highlightedText: NSLocalizedString("ui_onboarding_3_title_highlight", comment: "Onboarding screen 3 title highlight")
            ),
            description: (
                text: NSLocalizedString("ui_onboarding_3_body", comment: "Onboarding screen 3 body"),
                highlightedText: nil
            ),
            image: UIImage(named: "ico-onboarding-3")!,
            trackingEvent: .screenOnboarding3
        )
    ]

    private var completion: () -> () = { }

    convenience init(completion: @escaping () -> ()) {
        self.init()
        self.completion = completion
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        completelyNewLabel.setStyle(.callout)
        createSafeButton.setText(NSLocalizedString("button_next", comment: "Next button title"), .filled)

        // Hide legacy onboarding actions and top-right controls.
        loadSafeButton.isHidden = true
        demoButton.isHidden = true
        completelyNewLabel.isHidden = true
        skipButton.isHidden = true
        closeButton.isHidden = true
        let nib = UINib(nibName: OnboardingStepCollectionViewCell.identifier, bundle: Bundle(for: OnboardingStepCollectionViewCell.self))
        collectionView.register(nib, forCellWithReuseIdentifier: OnboardingStepCollectionViewCell.identifier)

        collectionView.delegate = self
        collectionView.dataSource = self

        pageControl.numberOfPages = self.steps.count
        actionsContainerView.isHidden = false
        bindCurrentStep(page: 0)
        overrideUserInterfaceStyle = .dark
    }

    @IBAction private func didTapLoadSafe(_ sender: Any) {
        Tracker.trackEvent(.addSafeFromOnboarding)
        addSafeFlow = AddSafeFlow(completion: { [weak self] _ in
            self?.addSafeFlow = nil
            self?.completion()
        })
        present(flow: addSafeFlow)
    }

    @IBAction private func didTapCreateSafe(_ sender: Any) {
        let nextPage = pageControl.currentPage + 1
        if nextPage < steps.count {
            let indexPath = IndexPath(item: nextPage, section: 0)
            collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: true)
            bindCurrentStep(page: nextPage)
        } else {
            completion()
        }
    }

    @IBAction private func didTapTryDemo(_ sender: Any) {
        let chain = Chain.mainnetChain()

        let demoAddress: Address = Address(exactly: Safe.demoAddress)
        let demoName = "Demo Safe"
        let safeVersion = "1.1.1"
        Safe.create(address: demoAddress.checksummed, version: safeVersion, name: demoName, chain: chain)

        App.shared.notificationHandler.safeAdded(address: demoAddress)
        completion()
        Tracker.trackEvent(.tryDemo)
    }

    @IBAction private func skipButtonTouched(_ sender: Any) {
        Tracker.trackEvent(.onboardingSkipped)
        // Skip directly to completion (which will show login)
        completion()
    }

    @IBAction func pageChanged(_ sender: Any) {
        let pc = sender as! UIPageControl
        collectionView.scrollToItem(at: IndexPath(item: pc.currentPage, section: 0),
                                        at: .centeredHorizontally, animated: true)
        bindCurrentStep(page: pc.currentPage)
    }

    private func bindCurrentStep(page: Int) {
        pageControl.currentPage = page

        let actionTitleKey = page == steps.count - 1
            ? "ui_onboarding_start_action"
            : "button_next"
        createSafeButton.setText(NSLocalizedString(actionTitleKey, comment: "Onboarding CTA title"), .filled)

        let step = steps[page]
        if let event = step.trackingEvent {
            Tracker.trackEvent(event)
        }
    }

    @IBAction func didTapClosed(_ sender: Any) {
        completion()
    }
}

extension OnboardingViewController: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return steps.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: OnboardingStepCollectionViewCell.identifier,
                                                      for: indexPath) as! OnboardingStepCollectionViewCell
        cell.configure(step: steps[indexPath.row])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: self.collectionView.frame.width, height: self.collectionView.frame.height)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let page = Int(collectionView.contentOffset.x) / Int(collectionView.frame.width)
        bindCurrentStep(page: page)
    }
}
