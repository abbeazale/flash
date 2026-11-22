import Charts
import SwiftData
import SwiftUI

private struct TrainingLoadInputSignature: Equatable {
    let runCount: Int
    let heartRateCount: Int
    let latestRun: Date?
    let maxHR: Int?
    let restingHR: Int?
    let birthdate: Date?
    let trimpSex: String?
    let today: Date
}

private enum TrainingLoadRange: String, CaseIterable, Identifiable {
    case threeMonths = "3M"
    case year = "1Y"
    case all = "All"

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .threeMonths: 90
        case .year: 365
        case .all: nil
        }
    }
}

/// Fitness (CTL), fatigue (ATL), and form from on-device training load.
struct TrainingLoadView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DailyLoad.day) private var days: [DailyLoad]
    @Query(sort: \CachedRunSummary.date) private var cachedRuns: [CachedRunSummary]
    @Query private var profiles: [RunnerProfile]
    @Query(filter: #Predicate<AnalyticsBackfillState> {
        $0.key == "avg-hr-v1"
    }) private var heartRateBackfillStates: [AnalyticsBackfillState]

    @State private var range: TrainingLoadRange = .threeMonths
    @State private var errorMessage: String?

    private var profile: RunnerProfile? {
        profiles.first { $0.key == RunnerProfile.singletonKey }
    }

    private var inputSignature: TrainingLoadInputSignature {
        TrainingLoadInputSignature(
            runCount: cachedRuns.count,
            heartRateCount: cachedRuns.filter { $0.avgHR != nil }.count,
            latestRun: cachedRuns.last?.date,
            maxHR: profile?.maxHR,
            restingHR: profile?.restingHR,
            birthdate: profile?.birthdate,
            trimpSex: profile?.trimpSexRaw,
            today: Calendar.current.startOfDay(for: Date())
        )
    }

    private var visibleDays: [DailyLoad] {
        guard let count = range.days, days.count > count else { return days }
        return Array(days.suffix(count))
    }

    /// Long ranges plot every 7th day so the chart stays light.
    private var plottedDays: [DailyLoad] {
        let visible = visibleDays
        guard visible.count > 400 else { return visible }
        var sampled = stride(from: 0, to: visible.count, by: 7).map { visible[$0] }
        if let last = visible.last, sampled.last?.day != last.day {
            sampled.append(last)
        }
        return sampled
    }

    var body: some View {
        ZStack {
            Color.flashBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let today = days.last {
                        currentCard(today)
                        chartCard
                        notes
                    } else {
                        Text(cachedRuns.isEmpty ? "No runs yet" : "Calculating…")
                            .font(Font.custom("CallingCode-Regular", size: 16))
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(Font.custom("CallingCode-Regular", size: 14))
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }
        }
        .foregroundStyle(.white)
        .navigationTitle("Training Load")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.flashBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task(id: inputSignature) {
            do {
                try TrainingLoadStore(context: modelContext).recompute()
                errorMessage = nil
            } catch {
                errorMessage = "Could not update training load: \(error.localizedDescription)"
            }
        }
    }

    private func currentCard(_ today: DailyLoad) -> some View {
        let status = TrainingLoadStatus(form: today.form)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(status.title)
                    .font(Font.custom("CallingCode-Regular", size: 32))
                    .foregroundStyle(color(for: status))
                Spacer()
                Text("Form \(Int(today.form.rounded()))")
                    .font(Font.custom("CallingCode-Regular", size: 16))
            }

            HStack {
                metric("Fitness", value: today.ctl, color: .blue)
                Spacer()
                metric("Fatigue", value: today.atl, color: .pink)
                Spacer()
                metric("Form", value: today.form, color: .green)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.18))
        .cornerRadius(8)
    }

    private func metric(_ title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(Int(value.rounded()))")
                .font(Font.custom("CallingCode-Regular", size: 22))
                .foregroundStyle(color)
            Text(title)
                .font(Font.custom("CallingCode-Regular", size: 12))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Range", selection: $range) {
                ForEach(TrainingLoadRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)

            Chart {
                ForEach(plottedDays, id: \.day) { day in
                    LineMark(x: .value("Day", day.day), y: .value("Load", day.ctl))
                        .foregroundStyle(by: .value("Series", "Fitness"))
                    LineMark(x: .value("Day", day.day), y: .value("Load", day.atl))
                        .foregroundStyle(by: .value("Series", "Fatigue"))
                    LineMark(x: .value("Day", day.day), y: .value("Load", day.form))
                        .foregroundStyle(by: .value("Series", "Form"))
                }
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .chartForegroundStyleScale([
                "Fitness": Color.blue,
                "Fatigue": Color.pink,
                "Form": Color.green,
            ])
            .chartLegend(position: .bottom)
            .chartXAxis {
                AxisMarks(position: .bottom) { _ in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.1))
                    AxisValueLabel()
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
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 8) {
            let estimated = visibleDays.filter(\.isEstimated).count
            if estimated > 0 {
                Text(estimatedText(count: estimated))
            }
            if let state = heartRateBackfillStates.first, !state.isComplete, state.totalCount > 0 {
                Text("Reading heart rate: \(state.processedCount)/\(state.totalCount) runs")
            }
            Text("Fitness is a 42-day weighted average of daily load, fatigue a 7-day one, and form is fitness minus fatigue. Fresh: form above 5. Fatigued: below -10.")
            Text("Rule-based maths on your runs. Not medical advice.")
        }
        .font(Font.custom("CallingCode-Regular", size: 12))
        .foregroundStyle(.white.opacity(0.6))
    }

    private func estimatedText(count: Int) -> String {
        let reason = (profile?.trimpSex ?? .notSet) == .notSet
            ? "Set TRIMP sex in Settings to use heart rate."
            : "Those runs have no heart-rate data."
        return "\(count) day\(count == 1 ? "" : "s") in this range use duration only. \(reason)"
    }

    private func color(for status: TrainingLoadStatus) -> Color {
        switch status {
        case .fresh: .green
        case .balanced: .white
        case .fatigued: .orange
        }
    }
}
