//
//  TokenPriceHistoryHeaderView.swift
//  Multisig
//

import UIKit
import DGCharts

final class TokenPriceHistoryHeaderView: UIView {
    private final class DayAxisValueFormatter: AxisValueFormatter {
        private let formatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale.autoupdatingCurrent
            f.timeZone = .autoupdatingCurrent
            f.dateFormat = "MMM d"
            return f
        }()

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

    private let chartView = LineChartView()
    private let placeholderLabel = UILabel()
    private let activity = UIActivityIndicatorView(style: .medium)

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
        chartView.xAxis.granularity = 24 * 60 * 60 // 1 day
        chartView.xAxis.labelCount = 4
        chartView.xAxis.valueFormatter = DayAxisValueFormatter()

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

        addSubview(chartView)
        addSubview(placeholderLabel)
        addSubview(activity)

        NSLayoutConstraint.activate([
            chartView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            chartView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            chartView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            chartView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            placeholderLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            placeholderLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),

            activity.centerXAnchor.constraint(equalTo: centerXAnchor),
            activity.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        showPlaceholder(text: "Chart coming soon")
    }

    func showLoading() {
        placeholderLabel.isHidden = true
        chartView.isHidden = true
        activity.isHidden = false
        activity.startAnimating()
    }

    func showPlaceholder(text: String = "Chart coming soon") {
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
}


