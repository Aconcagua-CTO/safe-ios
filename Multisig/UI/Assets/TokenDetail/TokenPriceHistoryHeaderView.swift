//
//  TokenPriceHistoryHeaderView.swift
//  Multisig
//

import UIKit
import DGCharts

final class TokenPriceHistoryHeaderView: UIView {
    enum Interval: Int, CaseIterable {
        case week
        case month
        case year

        var titleKey: String {
            switch self {
            case .week:
                return "ui_chart_interval_week"
            case .month:
                return "ui_chart_interval_month"
            case .year:
                return "ui_chart_interval_year"
            }
        }
    }

    private final class DateAxisValueFormatter: AxisValueFormatter {
        private let formatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale.autoupdatingCurrent
            f.timeZone = .autoupdatingCurrent
            return f
        }()

        init(dateFormat: String) {
            formatter.dateFormat = dateFormat
        }

        func stringForValue(_ value: Double, axis: AxisBase?) -> String {
            // x is epoch seconds
            formatter.string(from: Date(timeIntervalSince1970: value))
        }
    }

    private final class CompactNumberAxisValueFormatter: AxisValueFormatter {
        private let formatter: NumberFormatter = {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.locale = Locale.autoupdatingCurrent
            f.usesGroupingSeparator = true
            f.minimumFractionDigits = 0
            f.maximumFractionDigits = 2
            return f
        }()

        func stringForValue(_ value: Double, axis: AxisBase?) -> String {
            let absV = abs(value)
            let (scaled, suffix): (Double, String) = {
                if absV >= 1_000_000_000 { return (value / 1_000_000_000, "B") }
                if absV >= 1_000_000 { return (value / 1_000_000, "M") }
                if absV >= 1_000 { return (value / 1_000, "K") }
                return (value, "")
            }()
            let s = formatter.string(from: NSNumber(value: scaled)) ?? "\(scaled)"
            return s + suffix
        }
    }

    struct Point {
        let time: TimeInterval
        let value: Double
    }

    var onIntervalChanged: ((Interval) -> Void)?

    private let intervalControl = UISegmentedControl(items: Interval.allCases.map {
        NSLocalizedString($0.titleKey, comment: "Chart interval label")
    })
    private let chartView = LineChartView()
    private let placeholderLabel = UILabel()
    private let activity = UIActivityIndicatorView(style: .medium)
    private let dayFormatter = DateAxisValueFormatter(dateFormat: "MMM d")
    private let monthFormatter = DateAxisValueFormatter(dateFormat: "MMM")
    private(set) var selectedInterval: Interval = .week

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        backgroundColor = .backgroundPrimary

        intervalControl.translatesAutoresizingMaskIntoConstraints = false
        intervalControl.selectedSegmentIndex = selectedInterval.rawValue
        intervalControl.addTarget(self, action: #selector(intervalChanged), for: .valueChanged)

        chartView.translatesAutoresizingMaskIntoConstraints = false
        chartView.backgroundColor = .clear
        chartView.noDataText = ""
        chartView.legend.enabled = false
        chartView.rightAxis.enabled = false

        // Simple axes for context (minimal styling).
        chartView.xAxis.enabled = true
        chartView.xAxis.labelPosition = .bottom
        chartView.xAxis.drawGridLinesEnabled = false
        chartView.xAxis.drawAxisLineEnabled = true
        chartView.xAxis.labelTextColor = UIColor.secondaryLabel
        chartView.xAxis.axisLineColor = UIColor.tertiaryLabel
        chartView.xAxis.granularityEnabled = true

        chartView.leftAxis.enabled = true
        chartView.leftAxis.drawGridLinesEnabled = true
        chartView.leftAxis.gridColor = UIColor.tertiaryLabel.withAlphaComponent(0.35)
        chartView.leftAxis.gridLineWidth = 0.7
        chartView.leftAxis.drawAxisLineEnabled = false
        chartView.leftAxis.labelTextColor = UIColor.secondaryLabel
        chartView.leftAxis.labelCount = 4
        chartView.leftAxis.valueFormatter = CompactNumberAxisValueFormatter()

        chartView.minOffset = 0
        chartView.setScaleEnabled(false)
        chartView.pinchZoomEnabled = false
        chartView.doubleTapToZoomEnabled = false
        chartView.dragEnabled = false
        chartView.highlightPerTapEnabled = false
        chartView.highlightPerDragEnabled = false

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.setStyle(.body)
        placeholderLabel.textAlignment = .center
        placeholderLabel.numberOfLines = 0
        placeholderLabel.textColor = UIColor.secondaryLabel

        activity.translatesAutoresizingMaskIntoConstraints = false

        addSubview(intervalControl)
        addSubview(chartView)
        addSubview(placeholderLabel)
        addSubview(activity)

        let chartLeading = chartView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16)
        chartLeading.priority = UILayoutPriority(999)
        let chartTrailing = chartView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
        chartTrailing.priority = UILayoutPriority(999)

        let placeholderCenterX = placeholderLabel.centerXAnchor.constraint(equalTo: centerXAnchor)
        placeholderCenterX.priority = UILayoutPriority(750)
        let placeholderLeading = placeholderLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24)
        placeholderLeading.priority = UILayoutPriority(999)
        let placeholderTrailing = placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24)
        placeholderTrailing.priority = UILayoutPriority(999)

        let intervalLeading = intervalControl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16)
        intervalLeading.priority = UILayoutPriority(999)
        let intervalTrailing = intervalControl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
        intervalTrailing.priority = UILayoutPriority(999)
        let intervalCenterX = intervalControl.centerXAnchor.constraint(equalTo: centerXAnchor)
        intervalCenterX.priority = UILayoutPriority(750)

        NSLayoutConstraint.activate([
            intervalControl.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            intervalLeading,
            intervalTrailing,
            intervalCenterX,

            chartView.topAnchor.constraint(equalTo: intervalControl.bottomAnchor, constant: 12),
            chartLeading,
            chartTrailing,
            chartView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            placeholderCenterX,
            placeholderLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            placeholderLeading,
            placeholderTrailing,

            activity.centerXAnchor.constraint(equalTo: centerXAnchor),
            activity.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        applyAxisStyle(for: selectedInterval)
        showPlaceholder(text: NSLocalizedString("ui_chart_coming_soon", comment: "Chart placeholder"))
    }

    func showLoading() {
        placeholderLabel.isHidden = true
        chartView.isHidden = true
        activity.isHidden = false
        activity.startAnimating()
    }

    func showPlaceholder(text: String = NSLocalizedString("ui_chart_coming_soon", comment: "Chart placeholder")) {
        activity.stopAnimating()
        activity.isHidden = true
        chartView.isHidden = true
        placeholderLabel.isHidden = false
        placeholderLabel.text = text
    }

    func showChart(points: [Point]) {
        activity.stopAnimating()
        activity.isHidden = true
        placeholderLabel.isHidden = true
        chartView.isHidden = false

        let sorted = points.sorted { $0.time < $1.time }
        let entries = sorted.map { ChartDataEntry(x: $0.time, y: $0.value) }

        let set = LineChartDataSet(entries: entries, label: "")
        set.drawValuesEnabled = false
        set.drawCirclesEnabled = false
        set.drawCircleHoleEnabled = false
        set.lineWidth = 2
        set.mode = LineChartDataSet.Mode.cubicBezier
        set.setColor(UIColor.label)
        set.drawFilledEnabled = false
        set.highlightEnabled = false

        let data = LineChartData(dataSet: set)
        data.setDrawValues(false)
        chartView.data = data

        // Keep x range tight to the actual data points so axis labels are meaningful.
        if let first = sorted.first?.time, let last = sorted.last?.time, last > first {
            chartView.xAxis.axisMinimum = first
            chartView.xAxis.axisMaximum = last
        }
    }

    func setSelectedInterval(_ interval: Interval, notify: Bool = false) {
        guard interval != selectedInterval else { return }
        selectedInterval = interval
        intervalControl.selectedSegmentIndex = interval.rawValue
        applyAxisStyle(for: interval)
        if notify {
            onIntervalChanged?(interval)
        }
    }

    @objc private func intervalChanged() {
        guard let interval = Interval(rawValue: intervalControl.selectedSegmentIndex) else { return }
        setSelectedInterval(interval, notify: true)
    }

    private func applyAxisStyle(for interval: Interval) {
        switch interval {
        case .week:
            chartView.xAxis.granularity = 24 * 60 * 60
            chartView.xAxis.labelCount = 4
            chartView.xAxis.valueFormatter = dayFormatter
        case .month:
            chartView.xAxis.granularity = 7 * 24 * 60 * 60
            chartView.xAxis.labelCount = 4
            chartView.xAxis.valueFormatter = dayFormatter
        case .year:
            chartView.xAxis.granularity = 30 * 24 * 60 * 60
            chartView.xAxis.labelCount = 6
            chartView.xAxis.valueFormatter = monthFormatter
        }
    }
}


