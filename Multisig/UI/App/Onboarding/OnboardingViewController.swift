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
    
    private let steps: [OnboardingStep] = [OnboardingStep(title: (text: "Get Money, Grow Money",
                                                                  highlightedText: nil),
                                                          description: (text: "Use the most popular Ethereum-compatible networks, connect to dApps, get transaction notifications and more.",
                                                                        highlightedText: "connect to dApps"),
                                                          image: UIImage(named: "ico-onboarding-key")!,
                                                          trackingEvent: .screenOnboarding1)
    ]

    private var completion: () -> () = { }

    convenience init(completion: @escaping () -> ()) {
        self.init()
        self.completion = completion
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        completelyNewLabel.setStyle(.callout)
        loadSafeButton.setText("Load existing Safe Account", .bordered)
        createSafeButton.setText("Create new Safe Account", .filled)
        demoButton.setText("Explore Demo", .primary)
        skipButton.setText("Skip", .primary)
        let nib = UINib(nibName: OnboardingStepCollectionViewCell.identifier, bundle: Bundle(for: OnboardingStepCollectionViewCell.self))
        collectionView.register(nib, forCellWithReuseIdentifier: OnboardingStepCollectionViewCell.identifier)

        collectionView.delegate = self
        collectionView.dataSource = self

        pageControl.numberOfPages = self.steps.count
        actionsContainerView.isHidden = true
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
        Tracker.trackEvent(.createSafeFromOnboarding)
        createSafeFlow = CreateSafeFlow(completion: { [weak self] _ in
            self?.createSafeFlow = nil
            self?.completion()
        })
        present(flow: createSafeFlow, dismissableOnSwipe: false)
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

        // Always hide actions screen - we go directly to login after onboarding
        UIView.transition(with: actionsContainerView, duration: 0.4,
                          options: .transitionCrossDissolve,
                          animations: { [weak self] in
            guard let self = self else { return }
            self.actionsContainerView.isHidden = true
          })

        // Show close button on last page
        UIView.transition(with: skipButton, duration: 0.4,
                          options: .transitionCrossDissolve,
                          animations: { [weak self] in
            guard let self = self else { return }
            self.closeButton.isHidden = page != self.pageControl.numberOfPages - 1
          })

        // Hide skip button on last page (use close button instead)
        UIView.transition(with: skipButton, duration: 0.4,
                          options: .transitionCrossDissolve,
                          animations: { [weak self] in
            guard let self = self else { return }
            self.skipButton.isHidden = page == self.pageControl.numberOfPages - 1
          })

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
