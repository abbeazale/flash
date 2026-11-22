//
//  statsView.swift
//  flash
//
//  Created by abbe on 2024-05-30.
//
import Charts
import MapKit
import SwiftData
import SwiftUI

//stats of run
struct statsView: View {
    @EnvironmentObject private var manager: HealthManager
    @Query private var profiles: [RunnerProfile]
    let workout: RunningData
    @State private var cachedElevationSegments: [Double] = []
    @State private var selectedSplit: Int?

    private var unitPresentation: RunUnitPresentation {
        RunUnitPresentation(
            unit: profiles.first { $0.key == RunnerProfile.singletonKey }?.distanceUnit
                ?? .kilometers
        )
    }

    private var splitDistanceMeters: Double {
        unitPresentation.unit == .miles ? 1_609.344 : 1_000
    }

    /// Splits with the route index range each one covers, from the same function that
    /// calculates their pace.
    private var routeSplits: [RouteSplit] {
        RouteAnalyzer.splits(route: workout.route, segmentDistanceMeters: splitDistanceMeters)
    }

    var body: some View {
        let routeSplits = routeSplits
        let splits = routeSplits.isEmpty
            ? workout.pacePerKM
            : routeSplits.map {
                SegmentPace(kilometer: $0.number, pace: $0.paceMinutesPerKilometer, formattedPace: "")
            }
        let highlightedRange = selectedSplit.flatMap { number in
            routeSplits.first { $0.number == number }?.indexRange
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Splits")
                    .font(Font.custom("CallingCode-Regular", size: 24))
                    .padding(.bottom, 16)

                if !workout.route.isEmpty {
                    MapView(
                        route: workout.route,
                        region: .constant(MKCoordinateRegion()),
                        highlightedRange: highlightedRange
                    )
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 8)

                    Text(selectedSplit.map { "Showing split \($0). Tap it again to clear." }
                         ?? "Tap a split to show it on the map.")
                        .font(Font.custom("CallingCode-Regular", size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.bottom, 16)
                }
                HStack(spacing: 8) {
                    Text(unitPresentation.distanceLabel)
                        .frame(width: 20, alignment: .leading)

                    Text("Pace")
                        .frame(width: 60, alignment: .leading)

                    Spacer()
                }
                .font(Font.custom("CallingCode-Regular", size: 18))
                .padding(.horizontal)
                .padding(.bottom, 8)

                ForEach(splits, id: \.kilometer) { segment in
                    HStack(spacing: 8) {
                        Text("\(segment.kilometer)")
                            .font(Font.custom("CallingCode-Regular", size: 18))
                            .frame(width: 20, alignment: .leading)



                        Text(
                            unitPresentation.paceText(
                                fromMinutesPerKilometer: segment.pace
                            )
                        )
                            .font(Font.custom("CallingCode-Regular", size: 18))
                            .frame(width: 60, alignment: .leading)

                        Rectangle()
                            .fill(Color.blue)
                            .frame(
                                width: self.barWidth(for: segment.pace, among: splits),
                                height: 20
                            )
                            .cornerRadius(4)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.yellow.opacity(selectedSplit == segment.kilometer ? 0.18 : 0))
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard routeSplits.contains(where: { $0.number == segment.kilometer }) else { return }
                        selectedSplit = selectedSplit == segment.kilometer ? nil : segment.kilometer
                    }
                    .accessibilityAddTraits(routeSplits.isEmpty ? [] : .isButton)
                    .padding(.bottom, 4)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)

            // REDESIGNED ELEVATION SECTION
            VStack(alignment: .leading, spacing: 12){
                HStack(alignment: .firstTextBaseline) {
                    Text("Elevation")
                        .font(Font.custom("CallingCode-Regular", size: 24))

                    Spacer()

                    let elevations = workout.route.map { $0.altitude }
                    if let maxElevation = elevations.max(),
                       let minElevation = elevations.min() {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(unitPresentation.elevationText(fromMeters: maxElevation))
                                .font(Font.custom("CallingCode-Regular", size: 14))
                                .foregroundColor(.green)
                            Text(
                                "Avg: \(unitPresentation.elevationText(fromMeters: elevations.average()))"
                            )
                                .font(Font.custom("CallingCode-Regular", size: 14))
                                .foregroundColor(.green.opacity(0.8))
                            Text(unitPresentation.elevationText(fromMeters: minElevation))
                                .font(Font.custom("CallingCode-Regular", size: 14))
                                .foregroundColor(.green.opacity(0.6))
                        }
                    }
                }
                .padding(.horizontal)

                // Elevation Chart
                GeometryReader { geometry in
                    ZStack(alignment: .bottom) {
                        // Background grid
                        VStack(spacing: 0) {
                            ForEach(0..<5) { i in
                                Divider()
                                    .background(Color.white.opacity(0.1))
                                Spacer()
                            }
                        }

                        // Elevation bars
                        HStack(alignment: .bottom, spacing: 1) {
                            ForEach(Array(cachedElevationSegments.enumerated()), id: \.offset) { index, elevation in
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.green.opacity(0.8),
                                                Color.green.opacity(0.4)
                                            ]),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(
                                        width: max(2, (geometry.size.width - CGFloat(cachedElevationSegments.count)) / CGFloat(cachedElevationSegments.count)),
                                        height: max(5, elevationHeight(elevation, maxHeight: geometry.size.height))
                                    )
                                    .cornerRadius(1)
                            }
                        }
                    }
                }
                .frame(height: 180)
                .padding(.horizontal)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.05))
                )
                .padding(.horizontal)

                // Time labels
                HStack {
                    Text("0:00")
                        .font(Font.custom("CallingCode-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.6))

                    Spacer()

                    Text(workout.formattedDuration)
                        .font(Font.custom("CallingCode-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.horizontal, 24)

                // Total elevation gain
                if workout.elevation > 0 {
                    HStack {
                        Image(systemName: "arrow.up.right")
                            .foregroundColor(.green)
                        Text(
                            "Total Elevation Gain: \(unitPresentation.elevationText(fromMeters: workout.elevation))"
                        )
                            .font(Font.custom("CallingCode-Regular", size: 16))
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }
            .padding(.vertical)
            .frame(maxWidth: .infinity)

            // CADENCE SECTION
            cadenceSection

            // HEART RATE SECTION
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Heart Rate")
                        .font(Font.custom("CallingCode-Regular", size: 24))

                    Spacer()

                    if let maxHR = workout.heartRateData.map({ $0.heartRate }).max(),
                       let minHR = workout.heartRateData.map({ $0.heartRate }).min() {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(maxHR)) bpm")
                                .font(Font.custom("CallingCode-Regular", size: 14))
                                .foregroundColor(.red)
                            Text("Avg: \(Int(workout.heartRate)) bpm")
                                .font(Font.custom("CallingCode-Regular", size: 14))
                                .foregroundColor(.orange)
                            Text("\(Int(minHR)) bpm")
                                .font(Font.custom("CallingCode-Regular", size: 14))
                                .foregroundColor(.red.opacity(0.6))
                        }
                    }
                }
                .padding(.horizontal)

                // Heart Rate Chart
                if !workout.heartRateData.isEmpty {
                    HeartRateChart(data: workout.heartRateData, duration: workout.duration)
                } else {
                    Text("No heart rate data available")
                        .font(Font.custom("CallingCode-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal)
                }

                // Time labels
                let hrLastTime = workout.heartRateData.map { $0.relativeTime }.max() ?? 0
                let xMax = hrLastTime > 0 ? hrLastTime : workout.duration
                HStack {
                    Text("0:00")
                        .font(Font.custom("CallingCode-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.6))

                    Spacer()

                    Text(formatTime(xMax))
                        .font(Font.custom("CallingCode-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.horizontal, 24)
            }
            .padding(.vertical)
            .frame(maxWidth: .infinity)

            // HEART RATE ZONES SECTION
            VStack(alignment: .leading, spacing: 12) {
                Text("Heart Rate Zones")
                    .font(Font.custom("CallingCode-Regular", size: 24))
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                if !workout.heartRateZones.isEmpty {
                    ForEach(workout.heartRateZones) { zone in
                        HStack {
                            // Zone name and range
                            VStack(alignment: .leading, spacing: 4) {
                                Text(zone.zone)
                                    .font(Font.custom("CallingCode-Regular", size: 16))
                                    .foregroundColor(.white)
                                Text(zone.range)
                                    .font(Font.custom("CallingCode-Regular", size: 12))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            .frame(width: 100, alignment: .leading)

                            // Percentage bar
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(height: 30)
                                    .cornerRadius(6)

                                Rectangle()
                                    .fill(Color(hex: zone.color))
                                    .frame(width: zone.percentage > 0 ? max(8, CGFloat(zone.percentage) * 1.8) : 4, height: 30)
                                    .cornerRadius(6)
                            }

                            // Percentage text
                            Text(String(format: "%.1f%%", zone.percentage))
                                .font(Font.custom("CallingCode-Regular", size: 16))
                                .foregroundColor(.white)
                                .frame(width: 60, alignment: .trailing)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
                } else {
                    Text("No heart rate zone data available")
                        .font(Font.custom("CallingCode-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
            .frame(maxWidth: .infinity)
        }
        .background {
            Color.flashBackground
                .ignoresSafeArea()
        }
        .foregroundStyle(.white)
        .toolbarBackground(Color.flashBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            // Cache elevation segments once on appear
            cachedElevationSegments = elevationSegments()
        }
    }
}

extension statsView {
    // MARK: - Cadence Section
    private var cadenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Cadence")
                    .font(Font.custom("CallingCode-Regular", size: 24))

                Spacer()

                let cadenceValues = workout.cadenceData.map { $0.cadence }
                if let maxCadence = cadenceValues.max(),
                   let minCadence = cadenceValues.min() {
                    let averageCadence = cadenceValues.average()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(maxCadence)) spm")
                            .font(Font.custom("CallingCode-Regular", size: 14))
                            .foregroundColor(.blue)
                        Text("Avg: \(Int(averageCadence)) spm")
                            .font(Font.custom("CallingCode-Regular", size: 14))
                            .foregroundColor(.blue.opacity(0.8))
                        Text("\(Int(minCadence)) spm")
                            .font(Font.custom("CallingCode-Regular", size: 14))
                            .foregroundColor(.blue.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal)

            // Cadence Chart
            if !workout.cadenceData.isEmpty && workout.cadenceData.count >= 3 {
                cadenceChart
            } else {
                VStack(spacing: 8) {
                    Text("Not enough cadence data for this run")
                        .font(Font.custom("CallingCode-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.6))
                    Text("Data points: \(workout.cadenceData.count)")
                        .font(Font.custom("CallingCode-Regular", size: 12))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.horizontal)
                .onAppear {
                    print("❌ Cadence view: Only \(workout.cadenceData.count) points available (need 3+)")
                    if let first = workout.cadenceData.first {
                        print("   Sample point: cadence=\(first.cadence), time=\(first.relativeTime)")
                    }
                }
            }

            // Time labels
            let cadenceLastTime = workout.cadenceData.map { $0.relativeTime }.max() ?? 0
            HStack {
                Text("0:00")
                    .font(Font.custom("CallingCode-Regular", size: 14))
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

                Text(formatTime(cadenceLastTime > 0 ? cadenceLastTime : workout.duration))
                    .font(Font.custom("CallingCode-Regular", size: 14))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 24)
        }
        .padding(.vertical)
        .frame(maxWidth: .infinity)
    }

    private var cadenceChart: some View {
        CadenceChart(data: workout.cadenceData, duration: workout.duration)
    }

    // MARK: - Helper Functions
    private func barWidth(for pace: Double, among splits: [SegmentPace]) -> CGFloat {
        let maxPace = splits.map(\.pace).max() ?? 1
        let maxWidth: CGFloat = 200 // Fixed width for bars

        return CGFloat((pace / maxPace) * Double(maxWidth))
    }


    private func elevationSegments() -> [Double] {
        guard !workout.route.isEmpty else { return [] }

        let segmentCount = 60
        let segmentLength = max(1, workout.route.count / segmentCount)
        var segments: [Double] = []

        for i in stride(from: 0, to: workout.route.count, by: segmentLength) {
            let endIndex = min(i + segmentLength, workout.route.count)
            let segment = workout.route[i..<endIndex]
            let avgElevation = segment.map { $0.altitude }.average()
            segments.append(avgElevation)
        }

        return segments
    }

    private func elevationHeight(_ elevation: Double, maxHeight: CGFloat) -> CGFloat {
        guard !cachedElevationSegments.isEmpty else { return 5 }

        let maxElevation = cachedElevationSegments.max() ?? 1.0
        let minElevation = cachedElevationSegments.min() ?? 0.0
        let range = maxElevation - minElevation

        // Avoid division by zero for flat terrain
        guard range > 0 else { return maxHeight * 0.5 }

        let normalizedElevation = (elevation - minElevation) / range
        return CGFloat(normalizedElevation * Double(maxHeight * 0.9)) // Use 90% of height for better visibility
    }
}

// Helper to calculate the average of an array of Doubles
extension Array where Element == Double {
    func average() -> Double {
        return self.isEmpty ? 0 : self.reduce(0, +) / Double(self.count)
    }
}

// Helper to format seconds as mm:ss or h:mm:ss
private func formatTime(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    } else {
        return String(format: "%d:%02d", m, s)
    }
}

// Extension to create Color from hex string
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Scrubbable charts

/// Nearest point to `time` by relative time, or nil for an empty series.
private func nearestPoint<Point>(
    to time: Double?,
    in points: [Point],
    time relativeTime: (Point) -> Double
) -> Point? {
    guard let time, time.isFinite else { return nil }
    return points.min { abs(relativeTime($0) - time) < abs(relativeTime($1) - time) }
}

private struct ScrubLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Font.custom("CallingCode-Regular", size: 12))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.65)))
    }
}

/// Heart-rate line chart. Drag across it to read the nearest sample.
private struct HeartRateChart: View {
    let data: [HeartRateDataPoint]
    let duration: TimeInterval
    @State private var selectedTime: Double?

    var body: some View {
        let lastTime = data.map(\.relativeTime).max() ?? 0
        let xMax = lastTime > 0 ? lastTime : max(duration, 1)
        let values = data.map(\.heartRate)
        let yMax = (ceil((values.max() ?? 0) / 10) * 10) + 10
        let yMin = max(0, floor((values.min() ?? 0) / 10) * 10 - 10)
        let selected = nearestPoint(to: selectedTime, in: data, time: \.relativeTime)

        Chart {
            ForEach(Array(data.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Time", point.relativeTime),
                    y: .value("Heart Rate", point.heartRate)
                )
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(colors: [.red, .orange]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .lineStyle(StrokeStyle(lineWidth: 2))

                AreaMark(
                    x: .value("Time", point.relativeTime),
                    yStart: .value("Baseline", yMin),
                    yEnd: .value("Heart Rate", point.heartRate)
                )
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.red.opacity(0.3),
                            Color.orange.opacity(0.1)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            if let selected {
                RuleMark(x: .value("Selected", selected.relativeTime))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(
                        position: .top,
                        spacing: 4,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        ScrubLabel(text: "\(formatTime(selected.relativeTime)) · \(Int(selected.heartRate.rounded())) bpm")
                    }
                PointMark(
                    x: .value("Selected", selected.relativeTime),
                    y: .value("Heart Rate", selected.heartRate)
                )
                .foregroundStyle(.white)
                .symbolSize(40)
            }
        }
        .chartXSelection(value: $selectedTime)
        .chartXAxis {
            AxisMarks(position: .bottom) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.1))
                AxisTick().foregroundStyle(.clear)
                AxisValueLabel()
                    .foregroundStyle(.white.opacity(0.6))
                    .font(Font.custom("CallingCode-Regular", size: 12))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel()
                    .foregroundStyle(.white.opacity(0.6))
                    .font(Font.custom("CallingCode-Regular", size: 12))
            }
        }
        .chartXScale(domain: 0...xMax)
        .chartYScale(domain: yMin...yMax)
        .frame(height: 200)
        .padding(.top, 24)
        .padding(.horizontal)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
        .padding(.horizontal)
    }
}

/// Cadence line chart. Drag across it to read the nearest sample.
private struct CadenceChart: View {
    let data: [CadenceDataPoint]
    let duration: TimeInterval
    @State private var selectedTime: Double?

    var body: some View {
        let minCadence = data.map(\.cadence).min() ?? 0
        let maxCadence = data.map(\.cadence).max() ?? 200
        let yAxisMin = max(0, floor(minCadence / 10) * 10 - 10)
        let yAxisMax = ceil(maxCadence / 10) * 10 + 10
        let lastTime = data.map(\.relativeTime).max() ?? 0
        let xMax = lastTime > 0 ? lastTime : max(duration, 1)
        let selected = nearestPoint(to: selectedTime, in: data, time: \.relativeTime)

        Chart {
            ForEach(data, id: \.timestamp) { point in
                LineMark(
                    x: .value("Time", point.relativeTime),
                    y: .value("Cadence", point.cadence)
                )
                .foregroundStyle(Color.blue)
                .lineStyle(StrokeStyle(lineWidth: 3))

                AreaMark(
                    x: .value("Time", point.relativeTime),
                    yStart: .value("Baseline", yAxisMin),
                    yEnd: .value("Cadence", point.cadence)
                )
                .foregroundStyle(Color.blue.opacity(0.3))
            }

            if let selected {
                RuleMark(x: .value("Selected", selected.relativeTime))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(
                        position: .top,
                        spacing: 4,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        ScrubLabel(text: "\(formatTime(selected.relativeTime)) · \(Int(selected.cadence.rounded())) spm")
                    }
                PointMark(
                    x: .value("Selected", selected.relativeTime),
                    y: .value("Cadence", selected.cadence)
                )
                .foregroundStyle(.white)
                .symbolSize(40)
            }
        }
        .chartXSelection(value: $selectedTime)
        .chartXAxis {
            AxisMarks(position: .bottom) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.1))
                AxisTick().foregroundStyle(.clear)
                AxisValueLabel()
                    .foregroundStyle(.white.opacity(0.6))
                    .font(Font.custom("CallingCode-Regular", size: 12))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel()
                    .foregroundStyle(.white.opacity(0.6))
                    .font(Font.custom("CallingCode-Regular", size: 12))
            }
        }
        .chartXScale(domain: 0...xMax)
        .chartYScale(domain: yAxisMin...yAxisMax)
        .frame(height: 190)
        .padding(.horizontal, 14)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
        .padding(.horizontal)
    }
}
