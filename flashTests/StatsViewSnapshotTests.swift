import XCTest
import SwiftUI
import Charts
@testable import flash

@MainActor
final class StatsViewSnapshotTests: XCTestCase {
    func testCadenceChartTypical() throws {
        let series = CadenceFixtures.typicalSeries
        let stats = SeriesStats(values: series.map(\.cadence))
        let view = CadenceSnapshotCard(
            title: "Cadence",
            series: series,
            stats: stats,
            message: nil,
            duration: 600
        )

        try assertSnapshot(
            matching: view,
            named: "cadence_typical",
            size: CadenceFixtures.snapshotSize
        )
    }

    func testCadenceChartSparse() throws {
        let series = CadenceFixtures.sparseSeries
        let stats = SeriesStats(values: series.map(\.cadence))
        let view = CadenceSnapshotCard(
            title: "Cadence",
            series: series,
            stats: stats,
            message: "Not enough cadence data for this run.",
            duration: 120
        )

        try assertSnapshot(
            matching: view,
            named: "cadence_sparse",
            size: CadenceFixtures.snapshotSize
        )
    }

    func testCadenceChartEmpty() throws {
        let view = CadenceSnapshotCard(
            title: "Cadence",
            series: [],
            stats: nil,
            message: "Not enough cadence data for this run.",
            duration: 120
        )

        try assertSnapshot(
            matching: view,
            named: "cadence_empty",
            size: CadenceFixtures.snapshotSize
        )
    }
}

private enum CadenceFixtures {
    static let baseDate = Date(timeIntervalSinceReferenceDate: 0)
    static let snapshotSize = CGSize(width: 408, height: 320)

    static let cadenceValues: [Double] = [160, 162, 164, 168, 170, 172, 176, 178, 182, 185, 188, 190, 187, 184, 180, 176, 170, 168, 166, 164, 162]

    static let typicalSeries: [CadenceDataPoint] = cadenceValues.enumerated().map { index, value in
        let offset = Double(index * 15)
        return CadenceDataPoint(
            timestamp: baseDate.addingTimeInterval(offset),
            cadence: value,
            relativeTime: offset
        )
    }

    static let sparseSeries: [CadenceDataPoint] = [
        CadenceDataPoint(timestamp: baseDate, cadence: 165, relativeTime: 0),
        CadenceDataPoint(timestamp: baseDate.addingTimeInterval(60), cadence: 170, relativeTime: 60)
    ]
}

private struct CadenceSnapshotCard: View {
    let title: String
    let series: [CadenceDataPoint]
    let stats: SeriesStats?
    let message: String?
    let duration: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.custom("CallingCode-Regular", size: 24))
                .foregroundColor(.white)

            if let stats, series.count >= 3 {
                HStack(spacing: 20) {
                    SummaryMetric(label: "Max", value: "\(Int(stats.max.rounded())) spm", color: accentColor)
                    SummaryMetric(label: "Avg", value: "\(Int(stats.average.rounded())) spm", color: accentColor.opacity(0.8))
                    SummaryMetric(label: "Min", value: "\(Int(stats.min.rounded())) spm", color: accentColor.opacity(0.6))
                }
            }

            if let message {
                Text(message)
                    .font(.custom("CallingCode-Regular", size: 16))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                cadenceChart
            }
        }
        .padding(20)
        .frame(width: 360, alignment: .leading)
        .background(cardColor)
        .cornerRadius(16)
        .padding(24)
        .frame(width: CadenceFixtures.snapshotSize.width, height: CadenceFixtures.snapshotSize.height, alignment: .topLeading)
        .background(backgroundColor)
    }

    private var cadenceChart: some View {
        Chart {
            ForEach(Array(series.enumerated()), id: \.offset) { _, dataPoint in
                LineMark(
                    x: .value("Time", dataPoint.relativeTime),
                    y: .value("Cadence", dataPoint.cadence)
                )
                .lineStyle(.init(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .foregroundStyle(accentColor)

                AreaMark(
                    x: .value("Time", dataPoint.relativeTime),
                    y: .value("Cadence", dataPoint.cadence)
                )
                .foregroundStyle(accentColor.opacity(0.2))

                if shouldShowMarker(for: dataPoint) {
                    PointMark(
                        x: .value("Time", dataPoint.relativeTime),
                        y: .value("Cadence", dataPoint.cadence)
                    )
                    .symbol(
                        Circle()
                            .strokeBorder(accentColor, lineWidth: 2)
                            .background(Circle().fill(accentColor.opacity(0.4)))
                    )
                    .foregroundStyle(accentColor)
                }
            }
        }
        .chartXScale(domain: 0...duration)
        .chartXAxis { axis in
            AxisMarks(position: .bottom) { value in
                AxisGridLine().foregroundStyle(.clear)
                AxisTick().foregroundStyle(.clear)
                AxisValueLabel { value in
                    if let seconds = value.as(Double.self) {
                        Text(formatTime(seconds))
                            .foregroundColor(axisLabelColor)
                    }
                }
            }
        }
        .chartYAxis { axis in
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(gridColor)
                AxisValueLabel { value in
                    if let spm = value.as(Double.self) {
                        Text("\(Int(spm))")
                            .foregroundColor(axisLabelColor)
                    }
                }
            }
        }
        .frame(height: 220)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cadence chart, steps per minute over time")
    }

    private func shouldShowMarker(for dataPoint: CadenceDataPoint) -> Bool {
        let seconds = Int(round(dataPoint.relativeTime))
        return seconds % 15 == 0
    }

    private var accentColor: Color { Color(red: 0x3A / 255, green: 0x86 / 255, blue: 1.0) }
    private var cardColor: Color { Color(red: 0x36 / 255, green: 0x2E / 255, blue: 0x40 / 255) }
    private var backgroundColor: Color { Color(red: 0x16 / 255, green: 0x14 / 255, blue: 0x1A / 255) }
    private var gridColor: Color { Color.white.opacity(0.1) }
    private var axisLabelColor: Color { Color.white.opacity(0.7) }
}

private struct SummaryMetric: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.custom("CallingCode-Regular", size: 14))
                .foregroundColor(.white.opacity(0.7))
            Text(value)
                .font(.custom("CallingCode-Regular", size: 16))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func formatTime(_ seconds: TimeInterval) -> String {
    let totalSeconds = Int(seconds.rounded())
    let minutes = totalSeconds / 60
    let remainder = totalSeconds % 60
    return String(format: "%02d:%02d", minutes, remainder)
}
