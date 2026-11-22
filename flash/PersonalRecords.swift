import Foundation
import SwiftData

enum PersonalRecordKey {
    static let longest = "whole.longest"
    static let fastest = "whole.fastest"
    static let elevation = "whole.elevation"

    static let wholeRunKeys = [longest, fastest, elevation]

    /// Best-effort key for a standard distance, e.g. `distance.5000`. Value is elapsed seconds.
    static func distance(_ meters: Double) -> String {
        "distance.\(Int(meters.rounded()))"
    }

    static let distancePrefix = "distance."
}

struct PersonalRecordInput {
    let runUUID: UUID
    let date: Date
    let distance: Double
    let duration: Double
    let elevationGain: Double
}

struct PersonalRecordCandidate: Equatable {
    let key: String
    let value: Double
    let runUUID: UUID
    let date: Date
}

enum PersonalRecordEngine {
    static func wholeRunRecords(
        from inputs: [PersonalRecordInput]
    ) -> [String: PersonalRecordCandidate] {
        var records: [String: PersonalRecordCandidate] = [:]

        for input in inputs {
            if input.distance.isFinite, input.distance > 0 {
                merge(
                    PersonalRecordCandidate(
                        key: PersonalRecordKey.longest,
                        value: input.distance,
                        runUUID: input.runUUID,
                        date: input.date
                    ),
                    into: &records
                )
            }

            if input.distance.isFinite,
               input.distance >= 1_000,
               input.duration.isFinite,
               input.duration > 0 {
                let secondsPerKilometer = input.duration / (input.distance / 1_000)
                if secondsPerKilometer.isFinite, secondsPerKilometer > 0 {
                    merge(
                        PersonalRecordCandidate(
                            key: PersonalRecordKey.fastest,
                            value: secondsPerKilometer,
                            runUUID: input.runUUID,
                            date: input.date
                        ),
                        into: &records
                    )
                }
            }

            if input.elevationGain.isFinite, input.elevationGain >= 0 {
                merge(
                    PersonalRecordCandidate(
                        key: PersonalRecordKey.elevation,
                        value: input.elevationGain,
                        runUUID: input.runUUID,
                        date: input.date
                    ),
                    into: &records
                )
            }
        }

        return records
    }

    static func merge(
        _ candidate: PersonalRecordCandidate,
        into records: inout [String: PersonalRecordCandidate]
    ) {
        guard let existing = records[candidate.key] else {
            records[candidate.key] = candidate
            return
        }

        if isBetter(candidate, than: existing) {
            records[candidate.key] = candidate
        }
    }

    static func isBetter(
        _ candidate: PersonalRecordCandidate,
        than existing: PersonalRecordCandidate
    ) -> Bool {
        guard candidate.key == existing.key else { return false }

        if candidate.value != existing.value {
            return isMetricImprovement(
                key: candidate.key,
                newValue: candidate.value,
                oldValue: existing.value
            )
        }
        if candidate.date != existing.date {
            return candidate.date < existing.date
        }
        return candidate.runUUID.uuidString < existing.runUUID.uuidString
    }

    static func isMetricImprovement(key: String, newValue: Double, oldValue: Double) -> Bool {
        guard newValue.isFinite, oldValue.isFinite else { return false }
        switch key {
        case PersonalRecordKey.longest, PersonalRecordKey.elevation:
            return newValue > oldValue
        case PersonalRecordKey.fastest:
            return newValue > 0 && newValue < oldValue
        default:
            return key.hasPrefix("distance.") && newValue > 0 && newValue < oldValue
        }
    }
}

@MainActor
final class PersonalRecordStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func recomputeWholeRunRecords(from rows: [CachedRunSummary], now: Date = Date()) throws {
        let inputs = rows.map {
            PersonalRecordInput(
                runUUID: $0.healthKitUUID,
                date: $0.date,
                distance: $0.distance,
                duration: $0.duration,
                elevationGain: $0.elevationGain
            )
        }
        let candidates = PersonalRecordEngine.wholeRunRecords(from: inputs)
        let existingRecords = try context.fetch(FetchDescriptor<PersonalRecord>())
        var existingByKey = Dictionary(
            existingRecords.map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for key in PersonalRecordKey.wholeRunKeys {
            guard let candidate = candidates[key] else {
                if let staleRecord = existingByKey.removeValue(forKey: key) {
                    context.delete(staleRecord)
                }
                continue
            }

            if let record = existingByKey[key] {
                let selectionChanged = record.value != candidate.value
                    || record.runUUID != candidate.runUUID
                    || record.date != candidate.date
                guard selectionChanged else { continue }

                let improved = PersonalRecordEngine.isMetricImprovement(
                    key: key,
                    newValue: candidate.value,
                    oldValue: record.value
                )
                record.value = candidate.value
                record.runUUID = candidate.runUUID
                record.date = candidate.date
                record.computedAt = now
                record.isNew = improved
            } else {
                context.insert(
                    PersonalRecord(
                        key: candidate.key,
                        value: candidate.value,
                        runUUID: candidate.runUUID,
                        date: candidate.date,
                        computedAt: now,
                        isNew: false
                    )
                )
            }
        }

        try context.save()
    }

    /// Merges one run's best efforts into the stored records. Does not save; the caller saves
    /// together with the backfill cursor so both change in one transaction.
    /// - Parameter markNew: false during the initial history backfill, so old runs do not
    ///   appear as new PRs.
    func mergeBestEfforts(
        _ efforts: [Double: TimeInterval],
        runUUID: UUID,
        date: Date,
        markNew: Bool,
        now: Date = Date()
    ) throws {
        guard !efforts.isEmpty else { return }
        let existingRecords = try context.fetch(FetchDescriptor<PersonalRecord>())
        var existingByKey = Dictionary(
            existingRecords.map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for (meters, seconds) in efforts {
            guard seconds.isFinite, seconds > 0 else { continue }
            let candidate = PersonalRecordCandidate(
                key: PersonalRecordKey.distance(meters),
                value: seconds,
                runUUID: runUUID,
                date: date
            )

            guard let record = existingByKey[candidate.key] else {
                let record = PersonalRecord(
                    key: candidate.key,
                    value: candidate.value,
                    runUUID: candidate.runUUID,
                    date: candidate.date,
                    computedAt: now,
                    isNew: markNew
                )
                context.insert(record)
                existingByKey[candidate.key] = record
                continue
            }

            let existing = PersonalRecordCandidate(
                key: record.key,
                value: record.value,
                runUUID: record.runUUID,
                date: record.date
            )
            guard PersonalRecordEngine.isBetter(candidate, than: existing) else { continue }

            let improved = PersonalRecordEngine.isMetricImprovement(
                key: candidate.key,
                newValue: candidate.value,
                oldValue: existing.value
            )
            record.value = candidate.value
            record.runUUID = candidate.runUUID
            record.date = candidate.date
            record.computedAt = now
            record.isNew = markNew && improved
        }
    }

    /// Removes all standard-distance records, used when the route algorithm version changes.
    func deleteBestEffortRecords() throws {
        let records = try context.fetch(FetchDescriptor<PersonalRecord>())
        for record in records where record.key.hasPrefix(PersonalRecordKey.distancePrefix) {
            context.delete(record)
        }
    }
}
