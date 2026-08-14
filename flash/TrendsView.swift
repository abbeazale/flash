import Charts
import SwiftData
import SwiftUI

enum TrendsPeriod: String, CaseIterable, Identifiable {
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: "Month"
        case .year: "Year"
        }
    }

    var calendarComponent: Calendar.Component {
        switch self {
        case .month: .month
        case .year: .year
        }
    }
}

struct MonthTrendComparison: Equatable {
    let current: RunTotals
    let previous: RunTotals

    var distanceDelta: Double? {
        previous.distance > 0 ? current.distance - previous.distance : nil
    }

    var paceDelta: Double? {
        guard previous.distance > 0, current.avgPace > 0, previous.avgPace > 0 else {
            return nil
        }
        return current.avgPace - previous.avgPace
    }
}

enum TrendAnalytics {
    static func interval(
        for period: TrendsPeriod,
        containing date: Date,
        calendar: Calendar = .current
    ) -> DateInterval {
        calendar.dateInterval(of: period.calendarComponent, for: date)
            ?? DateInterval(start: date, end: date)
    }

    static func currentAndPreviousMonthIntervals(
        containing date: Date,
        calendar: Calendar = .current
    ) -> (current: DateInterval, previous: DateInterval) {
        let current = interval(for: .month, containing: date, calendar: calendar)
        let previousStart = calendar.date(byAdding: .month, value: -1, to: current.start)
            ?? current.start
        return (
            current,
            DateInterval(start: previousStart, end: current.start)
        )
    }

    static func monthComparison(
        _ runs: [RunSummaryData],
        containing date: Date = Date(),
        calendar: Calendar = .current
    ) -> MonthTrendComparison {
        let intervals = currentAndPreviousMonthIntervals(containing: date, calendar: calendar)
        return MonthTrendComparison(
            current: RunAggregator.totals(runs, in: intervals.current),
            previous: RunAggregator.totals(runs, in: intervals.previous)
        )
    }
}

struct RunUnitPresentation {
    let unit: PreferredDistanceUnit

    var distanceLabel: String {
        unit == .miles ? "mi" : "km"
    }

    var paceLabel: String {
        unit == .miles ? "/mi" : "/km"
    }

    var elevationLabel: String {
        unit == .miles ? "ft" : "m"
    }

    func distance(fromMeters meters: Double) -> Double {
        meters / (unit == .miles ? 1_609.344 : 1_000)
    }

    func elevation(fromMeters meters: Double) -> Double {
        unit == .miles ? meters * 3.28084 : meters
    }

    func pace(fromMinutesPerKilometer pace: Double) -> Double {
        unit == .miles ? pace * 1.609344 : pace
    }

    func distanceText(fromMeters meters: Double, signed: Bool = false) -> String {
        let value = distance(fromMeters: meters)
        return String(format: signed ? "%+.2f %@" : "%.2f %@", value, distanceLabel)
    }

    func elevationText(fromMeters meters: Double) -> String {
        String(format: "%.0f %@", elevation(fromMeters: meters), elevationLabel)
    }

    func paceText(fromMinutesPerKilometer pace: Double) -> String {
        guard pace.isFinite, pace > 0 else { return "N/A" }
        return Self.clockText(minutes: self.pace(fromMinutesPerKilometer: pace)) + paceLabel
    }

    func paceDeltaText(fromMinutesPerKilometer delta: Double) -> String {
        guard delta.isFinite else { return "Unavailable" }
        let direction = delta < 0 ? "faster" : delta > 0 ? "slower" : "unchanged"
        guard delta != 0 else { return direction }
        let convertedDelta = abs(pace(fromMinutesPerKilometer: delta))
        return "\(Self.clockText(minutes: convertedDelta))\(paceLabel) \(direction)"
    }

    static func durationText(_ duration: TimeInterval) -> String {
        guard duration.isFinite, duration >= 0 else { return "N/A" }
        let seconds = Int(duration.rounded())
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
    }

    private static func clockText(minutes: Double) -> String {
        let totalSeconds = Int((minutes * 60).rounded())
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private struct PaceTrendPoint: Identifiable {
    let id: Int
    let date: Date
    let pace: Double
}

struct TrendsView: View {
    @Query(sort: \CachedRunSummary.date) private var cachedRuns: [CachedRunSummary]
    @Query private var profiles: [RunnerProfile]

    @State private var selectedPeriod = TrendsPeriod.month

    private var summaries: [RunSummaryData] {
        cachedRuns.map(\.aggregateData)
    }

    private var unitPresentation: RunUnitPresentation {
        RunUnitPresentation(
            unit: profiles.first { $0.key == RunnerProfile.singletonKey }?.distanceUnit
                ?? .kilometers
        )
    }

    private var selectedTotals: RunTotals {
        let interval = TrendAnalytics.interval(for: selectedPeriod, containing: Date())
        return RunAggregator.totals(summaries, in: interval)
    }

    private var monthComparison: MonthTrendComparison {
        TrendAnalytics.monthComparison(summaries)
    }

    private var pacePoints: [PaceTrendPoint] {
        RunAggregator.paceSeries(summaries).enumerated().map { index, point in
            PaceTrendPoint(
                id: index,
                date: point.date,
                pace: unitPresentation.pace(fromMinutesPerKilometer: point.paceMinPerKm)
            )
        }
    }

    var body: some View {
        ZStack {
            Color.flashBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Picker("Period", selection: $selectedPeriod) {
                        ForEach(TrendsPeriod.allCases) { period in
                            Text(period.title).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)

                    periodSummary
                    monthComparisonCard
                    paceChart
                }
                .padding()
            }
        }
        .foregroundStyle(.white)
        .navigationTitle("Trends")
        .toolbarBackground(Color.flashBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var periodSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(periodTitle)
                .font(Font.custom("CallingCode-Regular", size: 24))

            metricRow(
                title: "Distance",
                value: unitPresentation.distanceText(fromMeters: selectedTotals.distance)
            )
            metricRow(title: "Time", value: RunUnitPresentation.durationText(selectedTotals.duration))
            metricRow(title: "Runs", value: String(selectedTotals.count))
            metricRow(
                title: "Elevation",
                value: unitPresentation.elevationText(fromMeters: selectedTotals.elevation)
            )
            metricRow(
                title: "Average pace",
                value: unitPresentation.paceText(fromMinutesPerKilometer: selectedTotals.avgPace)
            )
        }
        .analyticsCard()
    }

    private var monthComparisonCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("This month vs last month")
                .font(Font.custom("CallingCode-Regular", size: 24))

            if let distanceDelta = monthComparison.distanceDelta {
                metricRow(
                    title: "Distance",
                    value: unitPresentation.distanceText(
                        fromMeters: distanceDelta,
                        signed: true
                    )
                )

                if let paceDelta = monthComparison.paceDelta {
                    metricRow(
                        title: "Average pace",
                        value: unitPresentation.paceDeltaText(
                            fromMinutesPerKilometer: paceDelta
                        )
                    )
                } else {
                    metricRow(title: "Average pace", value: "Unavailable")
                }
            } else {
                Text("No previous-month distance to compare yet.")
                    .font(Font.custom("CallingCode-Regular", size: 14))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .analyticsCard()
    }

    private var paceChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pace over time")
                .font(Font.custom("CallingCode-Regular", size: 24))

            if pacePoints.isEmpty {
                Text(
                    "Run at least \(unitPresentation.distanceText(fromMeters: 1_000)) to start a pace trend."
                )
                    .font(Font.custom("CallingCode-Regular", size: 14))
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                Chart(pacePoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Pace", point.pace)
                    )
                    .foregroundStyle(Color.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Pace", point.pace)
                    )
                    .foregroundStyle(Color.blue)
                }
                .chartXAxis {
                    AxisMarks(position: .bottom) { _ in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.1))
                        AxisTick().foregroundStyle(.clear)
                        AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                            .foregroundStyle(.white.opacity(0.6))
                            .font(Font.custom("CallingCode-Regular", size: 11))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.1))
                        AxisValueLabel()
                            .foregroundStyle(.white.opacity(0.6))
                            .font(Font.custom("CallingCode-Regular", size: 11))
                    }
                }
                .frame(height: 240)

                Text(
                    "Minutes\(unitPresentation.paceLabel) • runs shorter than \(unitPresentation.distanceText(fromMeters: 1_000)) excluded"
                )
                    .font(Font.custom("CallingCode-Regular", size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .analyticsCard()
    }

    private var periodTitle: String {
        switch selectedPeriod {
        case .month:
            Date().formatted(.dateTime.month(.wide).year())
        case .year:
            Date().formatted(.dateTime.year())
        }
    }

    private func metricRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.white.opacity(0.65))
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(Font.custom("CallingCode-Regular", size: 16))
    }
}

private extension View {
    func analyticsCard() -> some View {
        padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.18))
            .cornerRadius(8)
    }
}
