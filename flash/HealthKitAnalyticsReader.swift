import CoreLocation
import Foundation
import HealthKit

/// Narrow HealthKit reads for history-wide analytics backfills. Unlike
/// `HealthManager.hydrateRunDetails`, each method fetches one thing only.
///
/// Missing data returns empty or nil. A HealthKit error throws, so a backfill does not mark a
/// run as processed because of a transient failure.
final class HealthKitAnalyticsReader {
    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    /// Route locations sorted by timestamp. A workout with no route, or a workout no longer
    /// in HealthKit, returns `[]`.
    func route(for workoutUUID: UUID) async throws -> [CLLocation] {
        guard let workout = try await workout(uuid: workoutUUID) else { return [] }
        let routes = try await routeSamples(for: workout)
        var locations: [CLLocation] = []
        for route in routes {
            locations.append(contentsOf: try await routeLocations(for: route))
        }
        return locations.sorted { $0.timestamp < $1.timestamp }
    }

    /// Average heart rate in bpm, or nil when the workout has no heart-rate samples.
    func averageHeartRate(for workoutUUID: UUID) async throws -> Double? {
        guard let workout = try await workout(uuid: workoutUUID) else { return nil }
        let heartRateType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForObjects(from: workout)
        let bpm = HKUnit.count().unitDivided(by: .minute())

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: heartRateType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, error in
                if let error {
                    if (error as? HKError)?.code == .errorNoData {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                let value = statistics?.averageQuantity()?.doubleValue(for: bpm)
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Internals

    private func workout(uuid: UUID) async throws -> HKWorkout? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: HKQuery.predicateForObject(with: uuid),
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples?.first as? HKWorkout)
                }
            }
            healthStore.execute(query)
        }
    }

    private func routeSamples(for workout: HKWorkout) async throws -> [HKWorkoutRoute] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKSeriesType.workoutRoute(),
                predicate: HKQuery.predicateForObjects(from: workout),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [
                    NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
                ]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [HKWorkoutRoute]) ?? [])
                }
            }
            healthStore.execute(query)
        }
    }

    private func routeLocations(for route: HKWorkoutRoute) async throws -> [CLLocation] {
        let collector = RouteLocationCollector()
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                collector.handle(
                    locations: locations,
                    done: done,
                    error: error,
                    continuation: continuation
                )
            }
            healthStore.execute(query)
        }
    }
}

/// Collects batched route locations and resumes the continuation exactly once.
private final class RouteLocationCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var locations: [CLLocation] = []
    private var finished = false

    func handle(
        locations batch: [CLLocation]?,
        done: Bool,
        error: Error?,
        continuation: CheckedContinuation<[CLLocation], Error>
    ) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        if let error {
            finished = true
            lock.unlock()
            continuation.resume(throwing: error)
            return
        }
        if let batch {
            locations.append(contentsOf: batch)
        }
        guard done else {
            lock.unlock()
            return
        }
        finished = true
        let result = locations
        lock.unlock()
        continuation.resume(returning: result)
    }
}
