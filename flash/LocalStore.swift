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
