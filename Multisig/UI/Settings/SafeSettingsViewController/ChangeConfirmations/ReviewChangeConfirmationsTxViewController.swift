//
// Created by Dirk Jäckel on 10.05.22.
// Copyright (c) 2022 Gnosis Ltd. All rights reserved.
//

import UIKit

class ReviewChangeConfirmationsTxViewController: ReviewSafeTransactionViewController {
    private var ownersCount: Int = 0
    private var oldThreshold: Int = 0
    private var newThreshold: Int = 0

    private var stepLabel: UILabel!

    var stepNumber: Int = 1
    var maxSteps: Int = 2

    var onSuccess: ((SCGModels.TransactionDetails) -> ())?

    var changeConfirmationsFlow: ChangeConfirmationsFlow!

    convenience init(safe: Safe, ownersCount: Int, oldThreshold: Int, newThreshold: Int) {
        self.init(safe: safe)
        self.ownersCount = ownersCount
        self.oldThreshold = oldThreshold
        self.newThreshold = newThreshold
        trackingEvent = .settingsTxAdvancedParams
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        assert(safe != nil)

        stepLabel = UILabel(frame: CGRect(x: 0, y: 0, width: 50, height: 21))
        stepLabel.textAlignment = .right
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: stepLabel)

        stepLabel.setStyle(.calloutTertiary)
        stepLabel.text = String(format: NSLocalizedString("ui_step_progress_format", comment: "Step progress format"),
                                stepNumber,
                                maxSteps)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Tracker.trackEvent(.reviewChangeConfirmations)
    }

    override func createSections() {
        sectionItems = [SectionItem.safeInfo(safeInfoCell()),
                        SectionItem.valueChange(confirmationsCell()),
                        SectionItem.valueChange(ownersCell()),
                        SectionItem.advanced(parametersCell())]
    }

    override func createTransaction() -> Transaction? {
        SafeTransactionController.shared.changeThreshold(
                safe: safe,
                safeTxGas: safeTxGas,
                nonce: nonce,
                threshold: newThreshold
        )
    }

    func confirmationsCell() -> UITableViewCell {
        let cell = tableView.dequeueCell(ValueChangeTableViewCell.self)
        cell.set(title: "Confirmations required",
                 valueBefore: String(format: NSLocalizedString("ui_step_out_of_format", comment: "Out of format"),
                                     oldThreshold,
                                     ownersCount),
                 valueAfter: String(format: NSLocalizedString("ui_step_out_of_format", comment: "Out of format"),
                                    newThreshold,
                                    ownersCount))
        return cell
    }

    func ownersCell() -> UITableViewCell {
        let cell = tableView.dequeueCell(ValueChangeTableViewCell.self)
        cell.set(title: "Safe Account owners", value: "\(ownersCount)")
        return cell
    }

    override func onSuccess(transaction: SCGModels.TransactionDetails) {
        onSuccess?(transaction)
    }

    override func getTrackingEvent() -> TrackingEvent {
        .settingsTxAdvancedParams
    }
}
