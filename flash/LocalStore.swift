import Foundation
import SwiftData

/// Lightweight cached mirror of a HealthKit running workout, for instant
/// history/aggregate reads without re-querying HealthKit each launch.
/// HealthKit remains the source of truth; this store is rebuildable.
@Model
final class CachedRunSummary {
    @Attribute(.unique) var healthKitUUID: UUID
    var date: Date
    var distance: Double       // meters
    var duration: Double       // seconds
    var calories: Double       // kcal
    var elevationGain: Double  // meters
    /// Average heart rate (bpm). Optional and populated lazily — the cheap bulk
    /// backfill leaves it nil (avg HR needs a per-run query); a later pass
    /// (Plan 002 / Phase E) fills it in. Declared here so Phase E needs no schema migration.
    var avgHR: Double?

    init(healthKitUUID: UUID, date: Date, distance: Double,
         duration: Double, calories: Double, elevationGain: Double, avgHR: Double? = nil) {
        self.healthKitUUID = healthKitUUID
        self.date = date
        self.distance = distance
        self.duration = duration
        self.calories = calories
        self.elevationGain = elevationGain
        self.avgHR = avgHR
    }
}

enum PreferredDistanceUnit: String, CaseIterable, Hashable, Identifiable {
    case kilometers
    case miles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kilometers: "Kilometers"
        case .miles: "Miles"
        }
    }
}

enum TRIMPSex: String, CaseIterable, Hashable, Identifiable {
    case notSet
    case female
    case male

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notSet: "Not set"
        case .female: "Female"
        case .male: "Male"
        }
    }
}

enum RunnerProfileValidationError: LocalizedError, Equatable {
    case maxHRMustBePositive
    case restingHRMustBePositive
    case birthdateCannotBeInFuture
    case restingHRMustBeBelowMax

    var errorDescription: String? {
        switch self {
        case .maxHRMustBePositive:
            "Maximum heart rate must be greater than zero."
        case .restingHRMustBePositive:
            "Resting heart rate must be greater than zero."
        case .birthdateCannotBeInFuture:
            "Birthdate cannot be in the future."
        case .restingHRMustBeBelowMax:
            "Resting heart rate must be lower than maximum heart rate."
        }
    }
}

struct RunnerProfileValues: Equatable {
    var maxHR: Int?
    var restingHR: Int?
    var birthdate: Date?
    var trimpSex: TRIMPSex
    var distanceUnit: PreferredDistanceUnit
}

@Model
final class RunnerProfile {
    static let singletonKey = "runner-profile"

    @Attribute(.unique) var key: String
    var maxHR: Int?
    var restingHR: Int?
    var birthdate: Date?
    var trimpSexRaw: String
    var distanceUnitRaw: String

    var trimpSex: TRIMPSex {
        get { TRIMPSex(rawValue: trimpSexRaw) ?? .notSet }
        set { trimpSexRaw = newValue.rawValue }
    }

    var distanceUnit: PreferredDistanceUnit {
        get { PreferredDistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers }
        set { distanceUnitRaw = newValue.rawValue }
    }

    var effectiveRestingHR: Int {
        restingHR ?? 60
    }

    init(
        key: String = RunnerProfile.singletonKey,
        maxHR: Int? = nil,
        restingHR: Int? = nil,
        birthdate: Date? = nil,
        trimpSexRaw: String = TRIMPSex.notSet.rawValue,
        distanceUnitRaw: String = PreferredDistanceUnit.kilometers.rawValue
    ) {
        self.key = key
        self.maxHR = maxHR
        self.restingHR = restingHR
        self.birthdate = birthdate
        self.trimpSexRaw = trimpSexRaw
        self.distanceUnitRaw = distanceUnitRaw
    }

    func effectiveMaxHR(on date: Date = Date(), calendar: Calendar = .current) -> Int {
        Self.effectiveMaxHR(maxHR: maxHR, birthdate: birthdate, on: date, calendar: calendar)
    }

    func validatedValues(on date: Date = Date(), calendar: Calendar = .current) throws -> RunnerProfileValues {
        try Self.validate(
            maxHR: maxHR,
            restingHR: restingHR,
            birthdate: birthdate,
            on: date,
            calendar: calendar
        )

        return values
    }

    var values: RunnerProfileValues {
        RunnerProfileValues(
            maxHR: maxHR,
            restingHR: restingHR,
            birthdate: birthdate,
            trimpSex: trimpSex,
            distanceUnit: distanceUnit
        )
    }

    func apply(_ values: RunnerProfileValues) {
        maxHR = values.maxHR
        restingHR = values.restingHR
        birthdate = values.birthdate
        trimpSex = values.trimpSex
        distanceUnit = values.distanceUnit
    }

    static func validate(
        maxHR: Int?,
        restingHR: Int?,
        birthdate: Date?,
        on date: Date = Date(),
        calendar: Calendar = .current
    ) throws {
        if let maxHR, maxHR <= 0 {
            throw RunnerProfileValidationError.maxHRMustBePositive
        }
        if let restingHR, restingHR <= 0 {
            throw RunnerProfileValidationError.restingHRMustBePositive
        }
        if let birthdate, birthdate > date {
            throw RunnerProfileValidationError.birthdateCannotBeInFuture
        }

        let effectiveMaxHR = Self.effectiveMaxHR(
            maxHR: maxHR,
            birthdate: birthdate,
            on: date,
            calendar: calendar
        )
        if let restingHR, restingHR >= effectiveMaxHR {
            throw RunnerProfileValidationError.restingHRMustBeBelowMax
        }
    }

    private static func effectiveMaxHR(
        maxHR: Int?,
        birthdate: Date?,
        on date: Date,
        calendar: Calendar
    ) -> Int {
        if let maxHR {
            return maxHR
        }
        if let birthdate,
           birthdate <= date,
           let age = calendar.dateComponents([.year], from: birthdate, to: date).year {
            let ageBasedMax = 220 - age
            if ageBasedMax > 0 {
                return ageBasedMax
            }
        }
        return 190
    }
}

@Model
final class PersonalRecord {
    @Attribute(.unique) var key: String
    var value: Double
    var runUUID: UUID
    var date: Date
    var computedAt: Date
    var isNew: Bool

    init(
        key: String,
        value: Double,
        runUUID: UUID,
        date: Date,
        computedAt: Date = Date(),
        isNew: Bool = false
    ) {
        self.key = key
        self.value = value
        self.runUUID = runUUID
        self.date = date
        self.computedAt = computedAt
        self.isNew = isNew
    }
}
