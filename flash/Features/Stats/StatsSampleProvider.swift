import Foundation
import HealthKit
import os

struct StatsSampleBatch<Sample: TimeSeriesSample>: Sendable {
    let samples: [Sample]
    let receivedAt: Date
}

protocol StatsSampleProviding {
    func prewarmHeartRate(for run: RunningData, last seconds: TimeInterval) async -> [HeartRateDataPoint]
    func heartRateStream(for run: RunningData) -> AsyncStream<StatsSampleBatch<HeartRateDataPoint>>
    func prewarmCadence(for run: RunningData, last seconds: TimeInterval) async -> [CadenceDataPoint]
    func cadenceStream(for run: RunningData) -> AsyncStream<StatsSampleBatch<CadenceDataPoint>>
}

struct DefaultStatsSampleProvider: StatsSampleProviding {
    private let healthKitProvider: HealthKitStatsSampleProvider?
    private let storedProvider = StoredRunStatsSampleProvider()

    init(healthStore: HKHealthStore? = HKHealthStore()) {
        if let healthStore, HKHealthStore.isHealthDataAvailable() {
            healthKitProvider = HealthKitStatsSampleProvider(healthStore: healthStore)
        } else {
            healthKitProvider = nil
        }
    }

    func prewarmHeartRate(for run: RunningData, last seconds: TimeInterval) async -> [HeartRateDataPoint] {
        if let healthKitProvider {
            let samples = await healthKitProvider.prewarmHeartRate(for: run, last: seconds)
            if !samples.isEmpty { return samples }
        }
        return await storedProvider.prewarmHeartRate(for: run, last: seconds)
    }

    func heartRateStream(for run: RunningData) -> AsyncStream<StatsSampleBatch<HeartRateDataPoint>> {
        if let healthKitProvider {
            let stream = healthKitProvider.heartRateStream(for: run)
            return AsyncStream { continuation in
                Task {
                    for await batch in stream {
                        continuation.yield(batch)
                    }
                    continuation.finish()
                }

                continuation.onTermination = { _ in }
            }
        }

        return storedProvider.heartRateStream(for: run)
    }

    func prewarmCadence(for run: RunningData, last seconds: TimeInterval) async -> [CadenceDataPoint] {
        if let healthKitProvider {
            let samples = await healthKitProvider.prewarmCadence(for: run, last: seconds)
            if !samples.isEmpty { return samples }
        }
        return await storedProvider.prewarmCadence(for: run, last: seconds)
    }

    func cadenceStream(for run: RunningData) -> AsyncStream<StatsSampleBatch<CadenceDataPoint>> {
        if let healthKitProvider {
            let stream = healthKitProvider.cadenceStream(for: run)
            return AsyncStream { continuation in
                Task {
                    for await batch in stream {
                        continuation.yield(batch)
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in }
            }
        }
        return storedProvider.cadenceStream(for: run)
    }
}

private struct StoredRunStatsSampleProvider: StatsSampleProviding {
    func prewarmHeartRate(for run: RunningData, last seconds: TimeInterval) async -> [HeartRateDataPoint] {
        guard seconds > 0 else { return run.heartRateData }
        let cutoff = max(0, run.duration - seconds)
        return run.heartRateData.filter { $0.relativeTime >= cutoff }
    }

    func heartRateStream(for run: RunningData) -> AsyncStream<StatsSampleBatch<HeartRateDataPoint>> {
        AsyncStream { continuation in
            if !run.heartRateData.isEmpty {
                continuation.yield(StatsSampleBatch(samples: run.heartRateData, receivedAt: Date()))
            }
            continuation.finish()
        }
    }

    func prewarmCadence(for run: RunningData, last seconds: TimeInterval) async -> [CadenceDataPoint] {
        guard seconds > 0 else { return run.cadenceData }
        let cutoff = max(0, run.duration - seconds)
        return run.cadenceData.filter { $0.relativeTime >= cutoff }
    }

    func cadenceStream(for run: RunningData) -> AsyncStream<StatsSampleBatch<CadenceDataPoint>> {
        AsyncStream { continuation in
            if !run.cadenceData.isEmpty {
                continuation.yield(StatsSampleBatch(samples: run.cadenceData, receivedAt: Date()))
            }
            continuation.finish()
        }
    }
}

private final class HealthKitStatsSampleProvider {
    private let healthStore: HKHealthStore
    private let anchorStore = StatsAnchorStore()
    private let logger = Logger(subsystem: "app.flash.stats", category: "HealthKitStream")
    private let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    private let cadenceType: HKQuantityType?
    private static let runningCadenceIdentifier = HKQuantityTypeIdentifier(rawValue: "HKQuantityTypeIdentifierRunningCadence")

    init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
        cadenceType = HKQuantityType.quantityType(forIdentifier: Self.runningCadenceIdentifier)
    }

    func prewarmHeartRate(for run: RunningData, last seconds: TimeInterval) async -> [HeartRateDataPoint] {
        await fetchQuantitySamples(
            type: heartRateType,
            start: max(run.date, run.date.addingTimeInterval(run.duration - seconds)),
            end: nil
        ).map { sample in
            makeHeartRatePoint(sample, runStart: run.date)
        }
    }

    func heartRateStream(for run: RunningData) -> AsyncStream<StatsSampleBatch<HeartRateDataPoint>> {
        AsyncStream { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: run.date, end: nil, options: .strictStartDate)
            var anchor = anchorStore.loadAnchor(for: .heartRate)

            let query = HKAnchoredObjectQuery(
                type: heartRateType,
                predicate: predicate,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { [weak self] _, samples, _, newAnchor, error in
                guard let self else { return }
                if let error { self.logger.error("Heart rate query error: \(error.localizedDescription, privacy: .public)") }
                anchor = newAnchor ?? anchor
                if let newAnchor { self.anchorStore.saveAnchor(newAnchor, for: .heartRate) }
                let points = (samples as? [HKQuantitySample])?.map { self.makeHeartRatePoint($0, runStart: run.date) } ?? []
                if !points.isEmpty {
                    continuation.yield(StatsSampleBatch(samples: points, receivedAt: Date()))
                }
            }

            query.updateHandler = { [weak self] _, samples, _, newAnchor, error in
                guard let self else { return }
                if let error { self.logger.error("Heart rate update error: \(error.localizedDescription, privacy: .public)") }
                if let newAnchor {
                    anchor = newAnchor
                    self.anchorStore.saveAnchor(newAnchor, for: .heartRate)
                }
                let points = (samples as? [HKQuantitySample])?.map { self.makeHeartRatePoint($0, runStart: run.date) } ?? []
                if !points.isEmpty {
                    continuation.yield(StatsSampleBatch(samples: points, receivedAt: Date()))
                }
            }

            self.healthStore.execute(query)
            continuation.onTermination = { [weak self] _ in
                if let query = query as HKQuery? {
                    self?.healthStore.stop(query)
                }
            }
        }
    }

    func prewarmCadence(for run: RunningData, last seconds: TimeInterval) async -> [CadenceDataPoint] {
        guard let cadenceType else { return [] }
        return await fetchQuantitySamples(
            type: cadenceType,
            start: max(run.date, run.date.addingTimeInterval(run.duration - seconds)),
            end: nil
        ).map { sample in
            makeCadencePoint(sample, runStart: run.date)
        }
    }

    func cadenceStream(for run: RunningData) -> AsyncStream<StatsSampleBatch<CadenceDataPoint>> {
        guard let cadenceType else { return AsyncStream { $0.finish() } }
        return AsyncStream { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: run.date, end: nil, options: .strictStartDate)
            var anchor = anchorStore.loadAnchor(for: .cadence)

            let query = HKAnchoredObjectQuery(
                type: cadenceType,
                predicate: predicate,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { [weak self] _, samples, _, newAnchor, error in
                guard let self else { return }
                if let error { self.logger.error("Cadence query error: \(error.localizedDescription, privacy: .public)") }
                anchor = newAnchor ?? anchor
                if let newAnchor { self.anchorStore.saveAnchor(newAnchor, for: .cadence) }
                let points = (samples as? [HKQuantitySample])?.map { self.makeCadencePoint($0, runStart: run.date) } ?? []
                if !points.isEmpty {
                    continuation.yield(StatsSampleBatch(samples: points, receivedAt: Date()))
                }
            }

            query.updateHandler = { [weak self] _, samples, _, newAnchor, error in
                guard let self else { return }
                if let error { self.logger.error("Cadence update error: \(error.localizedDescription, privacy: .public)") }
                if let newAnchor {
                    anchor = newAnchor
                    self.anchorStore.saveAnchor(newAnchor, for: .cadence)
                }
                let points = (samples as? [HKQuantitySample])?.map { self.makeCadencePoint($0, runStart: run.date) } ?? []
                if !points.isEmpty {
                    continuation.yield(StatsSampleBatch(samples: points, receivedAt: Date()))
                }
            }

            self.healthStore.execute(query)
            continuation.onTermination = { [weak self] _ in
                if let query = query as HKQuery? {
                    self?.healthStore.stop(query)
                }
            }
        }
    }

    private func fetchQuantitySamples(type: HKQuantityType, start: Date, end: Date?) async -> [HKQuantitySample] {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    self.logger.error("Sample fetch error: \(error.localizedDescription, privacy: .public)")
                }
                continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
            }
            healthStore.execute(query)
        }
    }

    private func makeHeartRatePoint(_ sample: HKQuantitySample, runStart: Date) -> HeartRateDataPoint {
        let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))
        let relativeTime = sample.startDate.timeIntervalSince(runStart)
        return HeartRateDataPoint(timestamp: sample.startDate, heartRate: bpm, relativeTime: relativeTime)
    }

    private func makeCadencePoint(_ sample: HKQuantitySample, runStart: Date) -> CadenceDataPoint {
        let spm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))
        let relativeTime = sample.startDate.timeIntervalSince(runStart)
        return CadenceDataPoint(timestamp: sample.startDate, cadence: spm, relativeTime: relativeTime)
    }
}

private final class StatsAnchorStore {
    private enum Key: String {
        case heartRate = "stats.anchor.heartRate"
        case cadence = "stats.anchor.cadence"
    }

    private let defaults = UserDefaults.standard

    func loadAnchor(for key: AnchorKey) -> HKQueryAnchor? {
        let storageKey = key.storageKey
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    func saveAnchor(_ anchor: HKQueryAnchor, for key: AnchorKey) {
        let storageKey = key.storageKey
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) {
            defaults.set(data, forKey: storageKey)
        }
    }

    enum AnchorKey {
        case heartRate
        case cadence

        var storageKey: String {
            switch self {
            case .heartRate: return Key.heartRate.rawValue
            case .cadence: return Key.cadence.rawValue
            }
        }
    }
}

