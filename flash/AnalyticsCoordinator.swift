import Foundation
import OSLog
import SwiftData

private let analyticsLogger = Logger(subsystem: "abbe.ca.flash", category: "Analytics")

enum AnalyticsBackfillKey {
    static let routeRecords = "pr-route-v1"
    static let routeRecordsVersion = 1
    static let averageHeartRate = "avg-hr-v1"
    static let averageHeartRateVersion = 1
}

/// Runs the history-wide analytics backfills after history sync: average HR for training
/// load, then route-based best efforts. Each backfill handles one run at a time and marks the
/// run as processed in the same save, so a killed app resumes with the next unmarked run.
///
/// All SwiftData work stays on the main actor. HealthKit reads suspend; they do not block it.
@MainActor
final class AnalyticsCoordinator {
    private static var isRunning = false
    private static let loadRecomputeBatch = 25

    private let context: ModelContext
    private let reader: HealthKitAnalyticsReader

    init(context: ModelContext, reader: HealthKitAnalyticsReader = HealthKitAnalyticsReader()) {
        self.context = context
        self.reader = reader
    }

    func run() async {
        guard !Self.isRunning else { return }
        Self.isRunning = true
        defer { Self.isRunning = false }

        let loadStore = TrainingLoadStore(context: context)
        perform("Training load") { try loadStore.recompute() }

        do {
            try await backfill(
                key: AnalyticsBackfillKey.averageHeartRate,
                version: AnalyticsBackfillKey.averageHeartRateVersion,
                marker: \.avgHRBackfillVersion,
                onReset: {},
                process: { [reader] row, _ in
                    guard row.avgHR == nil else { return }
                    let uuid = row.healthKitUUID
                    if let average = try await reader.averageHeartRate(for: uuid),
                       average.isFinite, average > 0 {
                        row.avgHR = average
                    }
                },
                afterEach: { processed in
                    if processed % Self.loadRecomputeBatch == 0 {
                        try loadStore.recompute()
                    }
                }
            )
        } catch {
            log("Average HR backfill", error)
        }
        perform("Training load") { try loadStore.recompute() }

        guard !Task.isCancelled else { return }
        let recordStore = PersonalRecordStore(context: context)
        do {
            try await backfill(
                key: AnalyticsBackfillKey.routeRecords,
                version: AnalyticsBackfillKey.routeRecordsVersion,
                marker: \.routeRecordsBackfillVersion,
                onReset: { try recordStore.deleteBestEffortRecords() },
                process: { [reader] row, markNew in
                    let uuid = row.healthKitUUID
                    let date = row.date
                    let route = try await reader.route(for: uuid)
                    let efforts = RouteAnalyzer.bestEfforts(route: route)
                    try recordStore.mergeBestEfforts(
                        efforts,
                        runUUID: uuid,
                        date: date,
                        markNew: markNew
                    )
                },
                afterEach: { _ in }
            )
        } catch {
            log("Route records backfill", error)
        }
    }

    // MARK: - Backfill loop

    /// Processes every cached run whose `marker` is not the current `version`, oldest first.
    /// A run is marked only after `process` succeeds, in the same save as the changes
    /// `process` made. An error rolls back the unsaved changes and stops the loop; the run
    /// stays unmarked and is retried on the next launch.
    private func backfill(
        key: String,
        version: Int,
        marker: ReferenceWritableKeyPath<CachedRunSummary, Int?>,
        onReset: () throws -> Void,
        process: (CachedRunSummary, _ markNew: Bool) async throws -> Void,
        afterEach: (Int) throws -> Void
    ) async throws {
        let state = try backfillState(key: key, version: version, onReset: onReset)
        let rows = try context.fetch(FetchDescriptor<CachedRunSummary>())
        let pending = BackfillOrder.pending(
            rows,
            isDone: { $0[keyPath: marker] == version },
            date: { $0.date },
            uuidString: { $0.healthKitUUID.uuidString }
        )

        state.totalCount = rows.count
        state.processedCount = rows.count - pending.count
        guard !pending.isEmpty else {
            state.isComplete = true
            try saveIfNeeded()
            return
        }
        try saveIfNeeded()

        // Only runs processed after the first full pass may be marked as new records.
        let markNew = state.isComplete
        var processedThisPass = 0

        for row in pending {
            if Task.isCancelled { return }
            guard row[keyPath: marker] != version else { continue }
            let date = row.date
            let uuidString = row.healthKitUUID.uuidString

            do {
                try await process(row, markNew)
                row[keyPath: marker] = version
                state.lastProcessedDate = date
                state.lastProcessedUUIDString = uuidString
                state.processedCount += 1
                try context.save()
            } catch {
                context.rollback()
                throw error
            }

            processedThisPass += 1
            try afterEach(processedThisPass)
        }

        state.isComplete = true
        try saveIfNeeded()
    }

    private func backfillState(
        key: String,
        version: Int,
        onReset: () throws -> Void
    ) throws -> AnalyticsBackfillState {
        var descriptor = FetchDescriptor<AnalyticsBackfillState>(
            predicate: #Predicate { $0.key == key }
        )
        descriptor.fetchLimit = 1

        if let state = try context.fetch(descriptor).first {
            if state.algorithmVersion != version {
                try onReset()
                state.reset(algorithmVersion: version)
                try context.save()
            }
            return state
        }

        try onReset()
        let state = AnalyticsBackfillState(key: key, algorithmVersion: version)
        context.insert(state)
        try context.save()
        return state
    }

    private func saveIfNeeded() throws {
        if context.hasChanges {
            try context.save()
        }
    }

    private func perform(_ label: String, _ work: () throws -> Void) {
        do {
            try work()
        } catch {
            log(label, error)
        }
    }

    private func log(_ label: String, _ error: Error) {
        analyticsLogger.error(
            "\(label, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
        )
    }
}

/// Rebuilds the full `DailyLoad` series from cached runs and the runner profile.
@MainActor
struct TrainingLoadStore {
    let context: ModelContext

    func recompute(today: Date = Date()) throws {
        let rows = try context.fetch(FetchDescriptor<CachedRunSummary>())
        let profile = try context.fetch(FetchDescriptor<RunnerProfile>())
            .first { $0.key == RunnerProfile.singletonKey }
        let runs = rows.map {
            TrainingLoadRun(date: $0.date, durationSeconds: $0.duration, averageHR: $0.avgHR)
        }
        let series = TrainingLoadEngine.dailySeries(
            runs: runs,
            settings: Self.settings(for: profile),
            today: today
        )

        let existing = try context.fetch(FetchDescriptor<DailyLoad>())
        var byDay = Dictionary(existing.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })

        for point in series {
            if let row = byDay.removeValue(forKey: point.day) {
                if row.load != point.load { row.load = point.load }
                if row.ctl != point.ctl { row.ctl = point.ctl }
                if row.atl != point.atl { row.atl = point.atl }
                if row.form != point.form { row.form = point.form }
                if row.isEstimated != point.isEstimated { row.isEstimated = point.isEstimated }
            } else {
                context.insert(DailyLoad(
                    day: point.day,
                    load: point.load,
                    ctl: point.ctl,
                    atl: point.atl,
                    form: point.form,
                    isEstimated: point.isEstimated
                ))
            }
        }

        for stale in byDay.values {
            context.delete(stale)
        }

        if context.hasChanges {
            try context.save()
        }
    }

    static func settings(for profile: RunnerProfile?) -> TrainingLoadSettings {
        let sex = profile?.trimpSex ?? .notSet
        return TrainingLoadSettings(
            maxHR: Double(profile?.effectiveMaxHR() ?? 190),
            restingHR: Double(profile?.effectiveRestingHR ?? 60),
            isFemale: sex == .notSet ? nil : sex == .female
        )
    }
}
