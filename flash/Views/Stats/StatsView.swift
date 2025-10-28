import SwiftUI
import Charts
#if canImport(UIKit)
import UIKit
#endif

struct StatsView: View {
    private let run: RunningData
    @StateObject private var viewModel: StatsViewModel

    @State private var heartRateSelection: HeartRateDataPoint?
    @State private var cadenceSelection: CadenceDataPoint?

    init(run: RunningData, sampleProvider: StatsSampleProviding = DefaultStatsSampleProvider()) {
        self.run = run
        _viewModel = StateObject(wrappedValue: StatsViewModel(run: run, sampleProvider: sampleProvider))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                heartRateSection
                cadenceSection
                splitsSection
                elevationSection
                heartRateZonesSection
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 16)
        }
        .background(StatsColors.background.ignoresSafeArea())
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .navigationTitle("Run Stats")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var heartRateSection: some View {
        StatsCard(title: "Heart Rate") {
            if let stats = viewModel.heartRateStats {
                HeartRateSummaryView(stats: stats)
            }

            if let message = viewModel.heartRateMessage {
                EmptyStateView(message: message)
            } else {
                heartRateChart
            }
        }
    }

    private var heartRateChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Chart {
                ForEach(Array(viewModel.heartRateSeries.enumerated()), id: \.offset) { _, dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.relativeTime),
                        y: .value("Heart Rate", dataPoint.heartRate)
                    )
                    .lineStyle(.init(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Gradient(colors: [.red, .orange]))

                    AreaMark(
                        x: .value("Time", dataPoint.relativeTime),
                        y: .value("Heart Rate", dataPoint.heartRate)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            Gradient(colors: [Color.red.opacity(0.25), Color.orange.opacity(0.05)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .chartXScale(domain: 0...run.duration)
            .chartXAxis { axis in
                AxisMarks(position: .bottom) { value in
                    AxisGridLine().foregroundStyle(.clear)
                    AxisTick().foregroundStyle(.clear)
                    AxisValueLabel { value in
                        if let seconds = value.as(Double.self) {
                            Text(formatTime(seconds))
                                .foregroundColor(StatsColors.axisLabel)
                        }
                    }
                }
            }
            .chartYAxis { axis in
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(StatsColors.grid)
                    AxisValueLabel { value in
                        if let bpm = value.as(Double.self) {
                            Text("\(Int(bpm))")
                                .foregroundColor(StatsColors.axisLabel)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    overlay(proxy: proxy, geometry: geometry, selection: $heartRateSelection, points: viewModel.heartRateSeries, indicatorColor: .red) { point in
                        "\(formatTime(point.relativeTime)), \(Int(point.heartRate.rounded())) bpm"
                    }
                }
            }
            .frame(height: 220)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Heart rate chart, beats per minute over time")
            .accessibilityValue(heartRateAccessibilityValue)
        }
    }

    private var heartRateAccessibilityValue: String {
        if let selection = heartRateSelection {
            return "\(formatTime(selection.relativeTime)), \(Int(selection.heartRate.rounded())) beats per minute"
        }
        if let stats = viewModel.heartRateStats {
            return "Average \(Int(stats.average.rounded())) beats per minute"
        }
        return "No heart rate data"
    }

    private var cadenceSection: some View {
        StatsCard(title: "Cadence") {
            if let stats = viewModel.cadenceStats, viewModel.cadenceSeries.count >= 3 {
                CadenceSummaryView(stats: stats)
            }

            if let message = viewModel.cadenceMessage {
                EmptyStateView(message: message)
            } else {
                cadenceChart
            }
        }
    }

    private var cadenceChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Chart {
                ForEach(Array(viewModel.cadenceSeries.enumerated()), id: \.offset) { _, dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.relativeTime),
                        y: .value("Cadence", dataPoint.cadence)
                    )
                    .lineStyle(.init(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(StatsColors.accent)

                    AreaMark(
                        x: .value("Time", dataPoint.relativeTime),
                        y: .value("Cadence", dataPoint.cadence)
                    )
                    .foregroundStyle(StatsColors.accent.opacity(0.2))

                    if shouldShowMarker(for: dataPoint) {
                        PointMark(
                            x: .value("Time", dataPoint.relativeTime),
                            y: .value("Cadence", dataPoint.cadence)
                        )
                        .symbol(Circle().strokeBorder(StatsColors.accent, lineWidth: 2).background(Circle().fill(StatsColors.accent.opacity(0.4))))
                        .foregroundStyle(StatsColors.accent)
                    }
                }
            }
            .chartXScale(domain: 0...run.duration)
            .chartYScale(domain: cadenceYDomain)
            .chartXAxis { axis in
                AxisMarks(position: .bottom) { value in
                    AxisGridLine().foregroundStyle(.clear)
                    AxisTick().foregroundStyle(.clear)
                    AxisValueLabel { value in
                        if let seconds = value.as(Double.self) {
                            Text(formatTime(seconds))
                                .foregroundColor(StatsColors.axisLabel)
                        }
                    }
                }
            }
            .chartYAxis { axis in
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(StatsColors.grid)
                    AxisValueLabel { value in
                        if let spm = value.as(Double.self) {
                            Text("\(Int(spm))")
                                .foregroundColor(StatsColors.axisLabel)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    overlay(proxy: proxy, geometry: geometry, selection: $cadenceSelection, points: viewModel.cadenceSeries, indicatorColor: StatsColors.accent) { point in
                        "\(formatTime(point.relativeTime)), \(Int(point.cadence.rounded())) spm"
                    }
                }
            }
            .frame(height: 220)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Cadence chart, steps per minute over time")
            .accessibilityValue(cadenceAccessibilityValue)
        }
    }

    private var cadenceAccessibilityValue: String {
        if let selection = cadenceSelection {
            return "\(formatTime(selection.relativeTime)), \(Int(selection.cadence.rounded())) steps per minute"
        }
        if let stats = viewModel.cadenceStats {
            return "Average \(Int(stats.average.rounded())) steps per minute"
        }
        return "No cadence data"
    }

    private var splitsSection: some View {
        StatsCard(title: "Splits") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Km")
                    Spacer()
                    Text("Pace")
                }
                .font(Fonts.body)
                .foregroundColor(.white.opacity(0.8))

                ForEach(run.pacePerKM, id: \.kilometer) { segment in
                    HStack(spacing: 16) {
                        Text("\(segment.kilometer)")
                            .font(Fonts.body)
                            .frame(width: 32, alignment: .leading)
                        Text(segment.formattedPace)
                            .font(Fonts.body)
                            .frame(width: 60, alignment: .leading)
                        GeometryReader { geometry in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(StatsColors.accent)
                                .frame(width: barWidth(for: segment.pace, width: geometry.size.width), height: 20)
                        }
                        .frame(height: 20)
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }

    private var elevationSection: some View {
        StatsCard(title: "Elevation") {
            if run.route.isEmpty {
                EmptyStateView(message: "No elevation data available")
            } else {
                ElevationView(run: run)
            }
        }
    }

    private var heartRateZonesSection: some View {
        StatsCard(title: "Heart Rate Zones") {
            if run.heartRateZones.isEmpty {
                EmptyStateView(message: "No heart rate zone data available")
            } else {
                VStack(spacing: 8) {
                    ForEach(run.heartRateZones) { zone in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(zone.zone)
                                    .font(Fonts.body)
                                    .foregroundColor(.white)
                                Text(zone.range)
                                    .font(Fonts.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            Spacer()
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(StatsColors.cardInner)
                                    .frame(height: 18)
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(hex: zone.color))
                                    .frame(width: max(18, CGFloat(zone.percentage) * 1.6), height: 18)
                            }
                            Text(String(format: "%.1f%%", zone.percentage))
                                .font(Fonts.body)
                                .foregroundColor(.white)
                                .frame(width: 60, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private func overlay<Sample: TimeSeriesSample>(
        proxy: ChartProxy,
        geometry: GeometryProxy,
        selection: Binding<Sample?>,
        points: [Sample],
        indicatorColor: Color,
        labelBuilder: @escaping (Sample) -> String
    ) -> some View {
        let plotFrame = geometry[proxy.plotAreaFrame]
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.clear).contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard let plotFrame, plotFrame.contains(value.location) else { return }
                            let relativeX = value.location.x - plotFrame.origin.x
                            if let time: Double = proxy.value(atX: relativeX) {
                                if let closest = points.closest(to: time) {
                                    let current = selection.wrappedValue
                                    if current?.relativeTime != closest.relativeTime {
                                        selection.wrappedValue = closest
#if os(iOS)
                                        UIAccessibility.post(notification: .announcement, argument: labelBuilder(closest))
#endif
                                    }
                                }
                            }
                        }
                        .onEnded { _ in
                            selection.wrappedValue = nil
                        }
                )

            if let selection = selection.wrappedValue, let xPosition = proxy.position(forX: selection.relativeTime) {
                let plotOrigin = plotFrame?.origin ?? .zero
                let x = xPosition + plotOrigin.x
                let label = labelBuilder(selection)
                VStack(alignment: .leading, spacing: 6) {
                    Text(label)
                        .font(Fonts.body)
                        .padding(8)
                        .background(StatsColors.cardInner.opacity(0.9))
                        .cornerRadius(8)
                    Rectangle()
                        .fill(indicatorColor)
                        .frame(width: 2, height: 140)
                }
                .position(x: x.clamped(to: geometry.size.width), y: plotOrigin.y + 20)
            }
        }
    }

    private func barWidth(for pace: Double, width: CGFloat) -> CGFloat {
        let maxPace = run.pacePerKM.map { $0.pace }.max() ?? 1
        let clampedWidth = max(0, width - 12)
        return max(20, CGFloat(pace / maxPace) * clampedWidth)
    }

    private var cadenceYDomain: ClosedRange<Double> {
        guard let stats = viewModel.cadenceStats else { return 120...220 }
        let minValue = floor(min(stats.min, 120) / 5) * 5
        let maxValue = ceil(max(stats.max, 220) / 5) * 5
        return max(0, minValue)...maxValue
    }

    private func shouldShowMarker(for dataPoint: CadenceDataPoint) -> Bool {
        let seconds = Int(round(dataPoint.relativeTime))
        return seconds % 15 == 0
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds.rounded())
        let minutes = totalSeconds / 60
        let remainder = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }
}

private struct StatsCard<Content: View>: View {
    let title: String
    let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(Fonts.title)
                .foregroundColor(.white)
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StatsColors.card)
        .cornerRadius(16)
    }
}

private struct EmptyStateView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(Fonts.body)
            .foregroundColor(.white.opacity(0.7))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HeartRateSummaryView: View {
    let stats: SeriesStats

    var body: some View {
        HStack(spacing: 20) {
            SummaryMetric(label: "Max", value: "\(Int(stats.max.rounded())) bpm", color: .red)
            SummaryMetric(label: "Avg", value: "\(Int(stats.average.rounded())) bpm", color: .orange)
            SummaryMetric(label: "Min", value: "\(Int(stats.min.rounded())) bpm", color: .red.opacity(0.7))
        }
    }
}

private struct CadenceSummaryView: View {
    let stats: SeriesStats

    var body: some View {
        HStack(spacing: 20) {
            SummaryMetric(label: "Max", value: "\(Int(stats.max.rounded())) spm", color: StatsColors.accent)
            SummaryMetric(label: "Avg", value: "\(Int(stats.average.rounded())) spm", color: StatsColors.accent.opacity(0.8))
            SummaryMetric(label: "Min", value: "\(Int(stats.min.rounded())) spm", color: StatsColors.accent.opacity(0.6))
        }
    }
}

private struct SummaryMetric: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Fonts.caption)
                .foregroundColor(.white.opacity(0.7))
            Text(value)
                .font(Fonts.body)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ElevationView: View {
    let run: RunningData

    private var elevations: [Double] {
        guard !run.route.isEmpty else { return [] }
        let segmentCount = 60
        let segmentLength = max(1, run.route.count / segmentCount)
        return stride(from: 0, to: run.route.count, by: segmentLength).map { index in
            let endIndex = min(index + segmentLength, run.route.count)
            let slice = run.route[index..<endIndex]
            let avg = slice.map { $0.altitude }.reduce(0, +) / Double(slice.count)
            return avg
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let maxElevation = elevations.max(), let minElevation = elevations.min() {
                HStack {
                    Text("Max \(Int(maxElevation)) m")
                        .font(Fonts.caption)
                        .foregroundColor(.green)
                    Spacer()
                    Text("Min \(Int(minElevation)) m")
                        .font(Fonts.caption)
                        .foregroundColor(.green.opacity(0.7))
                }
            }

            GeometryReader { geometry in
                let height = geometry.size.height
                HStack(alignment: .bottom, spacing: 1) {
                    ForEach(Array(elevations.enumerated()), id: \.offset) { _, value in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.green.opacity(0.8), Color.green.opacity(0.3)]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(
                                width: max(2, (geometry.size.width / CGFloat(max(elevations.count, 1))) - 1),
                                height: elevationHeight(value: value, min: elevations.min() ?? 0, max: elevations.max() ?? 1, maxHeight: height)
                            )
                    }
                }
            }
            .frame(height: 160)
            .background(StatsColors.cardInner)
            .cornerRadius(12)

            HStack {
                Text("0:00")
                    .font(Fonts.caption)
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Text(run.formattedDuration)
                    .font(Fonts.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    private func elevationHeight(value: Double, min: Double, max: Double, maxHeight: CGFloat) -> CGFloat {
        guard max > min else { return maxHeight * 0.4 }
        let normalized = (value - min) / (max - min)
        return CGFloat(normalized) * (maxHeight * 0.9)
    }
}

private enum StatsColors {
    static let background = Color(red: 0x16 / 255, green: 0x14 / 255, blue: 0x1A / 255)
    static let card = Color(red: 0x36 / 255, green: 0x2E / 255, blue: 0x40 / 255)
    static let cardInner = Color.white.opacity(0.06)
    static let grid = Color.white.opacity(0.1)
    static let axisLabel = Color.white.opacity(0.7)
    static let accent = Color("AccentBlue")
}

private enum Fonts {
    static let title = Font.custom("CallingCode-Regular", size: 24)
    static let body = Font.custom("CallingCode-Regular", size: 16)
    static let caption = Font.custom("CallingCode-Regular", size: 14)
}

private extension Array where Element: TimeSeriesSample {
    func closest(to relativeTime: Double) -> Element? {
        guard !isEmpty else { return nil }
        var low = 0
        var high = count - 1
        var best = self[0]
        while low <= high {
            let mid = (low + high) / 2
            let candidate = self[mid]
            if abs(candidate.relativeTime - relativeTime) < abs(best.relativeTime - relativeTime) {
                best = candidate
            }

            if candidate.relativeTime < relativeTime {
                low = mid + 1
            } else if candidate.relativeTime > relativeTime {
                if mid == 0 { break }
                high = mid - 1
            } else {
                return candidate
            }
        }
        return best
    }
}

private extension CGFloat {
    func clamped(to width: CGFloat) -> CGFloat {
        min(max(0, self), width)
    }
}
