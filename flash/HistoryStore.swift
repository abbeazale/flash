import Foundation
import HealthKit
import SwiftData

/// A plain-value snapshot of a run summary, used by the pure aggregation functions in
/// `RunAggregator` so the math is testable without SwiftData or HealthKit.
struct RunSummaryData {
    let date: Date
    let distance: Double       // meters
    let duration: Double       // seconds
    let elevationGain: Double  // meters
}

/// Rolled-up totals over a set of runs.
struct RunTotals: Equatable {
    var distance: Double = 0   // meters
    var duration: Double = 0   // seconds
    var count: Int = 0
    var elevation: Double = 0  // meters
    var avgPace: Double = 0    // min/km (0 when distance == 0)
}

/// Pure, deterministic aggregation over run summaries. No HealthKit, no SwiftData —
/// unit-tested directly (see `HistoryStoreTests`). Aggregates are derived on demand by
/// reducing the cached rows in memory; the run count is small enough that this is instant.
enum RunAggregator {
    static func totals(_ runs: [RunSummaryData]) -> RunTotals {
        var t = RunTotals()
        for r in runs {
            t.distance += r.distance
            t.duration += r.duration
            t.elevation += r.elevationGain
            t.count += 1
        }
        t.avgPace = t.distance > 0 ? (t.duration / 60.0) / (t.distance / 1000.0) : 0
        return t
    }

    static func totals(_ runs: [RunSummaryData], in interval: DateInterval) -> RunTotals {
        totals(runs.filter { interval.contains($0.date) })
    }

    /// 12 ordered buckets (month 1...12) for the given year; empty months are zeroed.
    static func monthlyTotals(_ runs: [RunSummaryData], year: Int,
                              calendar: Calendar = .current) -> [(month: Int, totals: RunTotals)] {
        (1...12).map { month in
            let inMonth = runs.filter {
                let c = calendar.dateComponents([.year, .month], from: $0.date)
                return c.year == year && c.month == month
            }
            return (month, totals(inMonth))
        }
    }

    /// One bucket per year that has runs, ascending by year.
    static func yearlyTotals(_ runs: [RunSummaryData],
                             calendar: Calendar = .current) -> [(year: Int, totals: RunTotals)] {
        let byYear = Dictionary(grouping: runs) { calendar.component(.year, from: $0.date) }
        return byYear.keys.sorted().map { ($0, totals(byYear[$0] ?? [])) }
    }

    /// Per-run average pace (min/km) for runs >= 1 km, ascending by date.
    static func paceSeries(_ runs: [RunSummaryData]) -> [(date: Date, paceMinPerKm: Double)] {
        runs.filter { $0.distance >= 1000 }
            .sorted { $0.date < $1.date }
            .map { (date: $0.date, paceMinPerKm: ($0.duration / 60.0) / ($0.distance / 1000.0)) }
    }
}

enum HistorySyncLaunchGate {
    static func shouldRun(authorizationFinished: Bool, authorizationSucceeded: Bool) -> Bool {
        authorizationFinished && authorizationSucceeded
    }
}

/// Bulk-loads and incrementally syncs HealthKit running-workout *summaries* into the SwiftData
/// `CachedRunSummary` cache, and exposes aggregate reads for trends/analytics. HealthKit stays
/// the source of truth; this cache is rebuildable.
@MainActor
final class HistoryStore {
    private let healthStore = HKHealthStore()
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Sync

    /// First-run backfill: if the cache is empty, pull every running workout summary.
    func backfillIfNeeded() async throws {
        let count = try context.fetchCount(FetchDescriptor<CachedRunSummary>())
        guard count == 0 else { return }
        let workouts = try await fetchRunningWorkouts(after: nil)
        try upsert(workouts)
    }

    /// Incremental: pull only workouts on/after the latest cached date (date-cursor). Does not
    /// detect edited/deleted HealthKit workouts — upgrade to `HKAnchoredObjectQuery` if needed.
    func sync() async throws {
        var descriptor = FetchDescriptor<CachedRunSummary>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let latest = try context.fetch(descriptor).first?.date
        let workouts = try await fetchRunningWorkouts(after: latest)
        try upsert(workouts)
    }

    // MARK: - Aggregate reads (cache-backed)

    func totals(in interval: DateInterval) throws -> RunTotals {
        RunAggregator.totals(try allSummaries(), in: interval)
    }

    func monthlyTotals(year: Int) throws -> [(month: Int, totals: RunTotals)] {
        RunAggregator.monthlyTotals(try allSummaries(), year: year)
    }

    func yearlyTotals() throws -> [(year: Int, totals: RunTotals)] {
        RunAggregator.yearlyTotals(try allSummaries())
    }

    func paceSeries() throws -> [(date: Date, paceMinPerKm: Double)] {
        RunAggregator.paceSeries(try allSummaries())
    }

    // MARK: - Internals

    private func allSummaries() throws -> [RunSummaryData] {
        let descriptor = FetchDescriptor<CachedRunSummary>(sortBy: [SortDescriptor(\.date)])
        let rows = try context.fetch(descriptor)
        return rows.map {
            RunSummaryData(
                date: $0.date,
                distance: $0.distance,
                duration: $0.duration,
                elevationGain: $0.elevationGain
            )
        }
    }

    /// Cheap summary-only HealthKit query — no routes or HR sub-queries. `startDate == nil`
    /// pulls all history; otherwise only workouts on/after the cursor.
    private func fetchRunningWorkouts(after startDate: Date?) async throws -> [HKWorkout] {
        let workoutType = HKSampleType.workoutType()
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let predicate: NSPredicate
        if let startDate {
            let datePredicate = HKQuery.predicateForSamples(
                withStart: startDate,
                end: nil,
                options: .strictStartDate
            )
            predicate = NSCompoundPredicate(
                andPredicateWithSubpredicates: [runningPredicate, datePredicate]
            )
        } else {
            predicate = runningPredicate
        }

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [
                    NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
                ]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
                }
            }
            healthStore.execute(query)
        }
    }

    /// Insert-or-update each workout's summary, keyed by HealthKit UUID. Leaves `avgHR` nil — it
    /// needs a per-run query and would defeat this cheap bulk fetch; Plan 002 / Phase E fills it.
    private func upsert(_ workouts: [HKWorkout]) throws {
        guard !workouts.isEmpty else { return }

        let existingRows = try context.fetch(FetchDescriptor<CachedRunSummary>())
        var byUUID = Dictionary(
            existingRows.map { ($0.healthKitUUID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for workout in workouts {
            let uuid = workout.uuid
            let distance = workout.totalDistance?.doubleValue(for: .meter()) ?? 0
            let duration = workout.duration
            let calories = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0
            var elevation = 0.0
            if let quantity = workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity {
                elevation = quantity.doubleValue(for: .meter())
            }

            if let existing = byUUID[uuid] {
                existing.date = workout.startDate
                existing.distance = distance
                existing.duration = duration
                existing.calories = calories
                existing.elevationGain = elevation
            } else {
                let summary = CachedRunSummary(
                    healthKitUUID: uuid,
                    date: workout.startDate,
                    distance: distance,
                    duration: duration,
                    calories: calories,
                    elevationGain: elevation
                )
                context.insert(summary)
                byUUID[uuid] = summary
            }
        }

        try context.save()
    }
}
