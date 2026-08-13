import SwiftData
import SwiftUI

private struct RecordRunSignature: Equatable {
    let uuid: UUID
    let date: Date
    let distance: Double
    let duration: Double
    let elevation: Double
}

struct PRView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PersonalRecord.key) private var records: [PersonalRecord]
    @Query(sort: \CachedRunSummary.date) private var cachedRuns: [CachedRunSummary]
    @Query private var profiles: [RunnerProfile]

    @State private var isComputing = false
    @State private var errorMessage: String?

    private var unitPresentation: RunUnitPresentation {
        RunUnitPresentation(
            unit: profiles.first { $0.key == RunnerProfile.singletonKey }?.distanceUnit
                ?? .kilometers
        )
    }

    private var inputSignature: [RecordRunSignature] {
        cachedRuns.map {
            RecordRunSignature(
                uuid: $0.healthKitUUID,
                date: $0.date,
                distance: $0.distance,
                duration: $0.duration,
                elevation: $0.elevationGain
            )
        }
    }

    var body: some View {
        ZStack {
            Color.flashBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isComputing && records.isEmpty {
                        HStack {
                            ProgressView()
                                .tint(.white)
                            Text("Computing records…")
                        }
                        .font(Font.custom("CallingCode-Regular", size: 14))
                        .foregroundStyle(.white.opacity(0.7))
                    }

                    recordCard(
                        title: "Longest run",
                        key: PersonalRecordKey.longest
                    )
                    recordCard(
                        title: "Fastest run",
                        key: PersonalRecordKey.fastest
                    )
                    recordCard(
                        title: "Most elevation",
                        key: PersonalRecordKey.elevation
                    )

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
        .navigationTitle("Personal Records")
        .toolbarBackground(Color.flashBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task(id: inputSignature) {
            await recomputeRecords()
        }
    }

    @ViewBuilder
    private func recordCard(title: String, key: String) -> some View {
        let record = records.first { $0.key == key }
        let run = record.flatMap { record in
            cachedRuns.first { $0.healthKitUUID == record.runUUID }
        }

        if let record, let run {
            NavigationLink {
                DetailedRun(workout: RunSummaryAdapter.runningData(from: run))
            } label: {
                recordLabel(title: title, record: record)
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(Font.custom("CallingCode-Regular", size: 20))
                Text(cachedRuns.isEmpty ? "No runs yet" : "No qualifying run")
                    .font(Font.custom("CallingCode-Regular", size: 14))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .recordCardStyle()
        }
    }

    private func recordLabel(title: String, record: PersonalRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(Font.custom("CallingCode-Regular", size: 20))
                Spacer()
                if record.isNew {
                    Text("NEW PR")
                        .font(Font.custom("CallingCode-Regular", size: 11))
                        .foregroundStyle(.green)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }

            Text(valueText(for: record))
                .font(Font.custom("CallingCode-Regular", size: 28))

            Text(record.date.formatted(.dateTime.day().month(.wide).year()))
                .font(Font.custom("CallingCode-Regular", size: 13))
                .foregroundStyle(.white.opacity(0.6))
        }
        .recordCardStyle()
    }

    private func valueText(for record: PersonalRecord) -> String {
        switch record.key {
        case PersonalRecordKey.longest:
            unitPresentation.distanceText(fromMeters: record.value)
        case PersonalRecordKey.fastest:
            unitPresentation.paceText(fromMinutesPerKilometer: record.value / 60)
        case PersonalRecordKey.elevation:
            unitPresentation.elevationText(fromMeters: record.value)
        default:
            "N/A"
        }
    }

    @MainActor
    private func recomputeRecords() async {
        isComputing = true
        defer { isComputing = false }

        do {
            try PersonalRecordStore(context: modelContext)
                .recomputeWholeRunRecords(from: cachedRuns)
            errorMessage = nil
        } catch {
            errorMessage = "Could not update records: \(error.localizedDescription)"
        }
    }
}

private extension View {
    func recordCardStyle() -> some View {
        padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.18))
            .cornerRadius(8)
    }
}
