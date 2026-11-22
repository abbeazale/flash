import CoreLocation
import Foundation

/// One split of a route, with the route index range it covers so the map can highlight
/// exactly the points used to calculate it.
struct RouteSplit: Equatable {
    let number: Int
    let distance: Double          // meters
    let duration: TimeInterval    // seconds
    let indexRange: ClosedRange<Int>

    var paceMinutesPerKilometer: Double {
        guard distance > 0, duration.isFinite else { return 0 }
        return duration / 60 / (distance / 1_000)
    }
}

/// Cumulative distance and elapsed time at one accepted route point.
struct RouteSample: Equatable {
    let distance: Double       // meters from the first accepted point
    let time: TimeInterval     // seconds from the first accepted point
}

/// Pure route math shared by personal records and the run-detail splits. No HealthKit,
/// SwiftData, or UI dependencies.
enum RouteAnalyzer {
    /// Standard best-effort targets in meters: 1K, 1 mile, 5K, 10K, half, marathon.
    static let standardDistances: [Double] = [1_000, 1_609.344, 5_000, 10_000, 21_097.5, 42_195]

    // MARK: - Best efforts

    /// Sorts points by timestamp and drops points that cannot be measured: non-finite
    /// coordinates, and points whose timestamp does not advance past the last kept point.
    static func normalized(_ route: [CLLocation]) -> [CLLocation] {
        let sorted = route.enumerated().sorted { lhs, rhs in
            if lhs.element.timestamp != rhs.element.timestamp {
                return lhs.element.timestamp < rhs.element.timestamp
            }
            return lhs.offset < rhs.offset
        }.map(\.element)

        var kept: [CLLocation] = []
        kept.reserveCapacity(sorted.count)
        for point in sorted {
            let coordinate = point.coordinate
            guard coordinate.latitude.isFinite, coordinate.longitude.isFinite,
                  CLLocationCoordinate2DIsValid(coordinate) else { continue }
            if let last = kept.last {
                guard point.timestamp > last.timestamp else { continue }
                guard point.distance(from: last).isFinite else { continue }
            }
            kept.append(point)
        }
        return kept
    }

    /// Cumulative distance/time samples over already-normalized points.
    static func cumulativeSamples(_ points: [CLLocation]) -> [RouteSample] {
        guard let first = points.first else { return [] }
        var samples = [RouteSample(distance: 0, time: 0)]
        samples.reserveCapacity(points.count)
        var distance = 0.0
        var previous = first
        for point in points.dropFirst() {
            distance += point.distance(from: previous)
            samples.append(RouteSample(
                distance: distance,
                time: point.timestamp.timeIntervalSince(first.timestamp)
            ))
            previous = point
        }
        return samples
    }

    /// Best elapsed seconds for each target the route is long enough to cover.
    static func bestEfforts(
        route: [CLLocation],
        targets: [Double] = standardDistances
    ) -> [Double: TimeInterval] {
        let samples = cumulativeSamples(normalized(route))
        var results: [Double: TimeInterval] = [:]
        for target in targets {
            if let seconds = bestEffort(samples: samples, targetMeters: target) {
                results[target] = seconds
            }
        }
        return results
    }

    /// Fastest time to cover `targetMeters`, interpolating linearly inside the boundary
    /// segment. The optimum of a piecewise-linear window lies where either end touches a
    /// sample, so one sweep anchors the start at samples and a second anchors the end.
    static func bestEffort(samples: [RouteSample], targetMeters: Double) -> TimeInterval? {
        guard targetMeters.isFinite, targetMeters > 0,
              let total = samples.last?.distance, total >= targetMeters else { return nil }

        var best = Double.infinity

        // Start at sample i; interpolate where the window reaches target distance.
        var j = 0
        for i in samples.indices {
            let endDistance = samples[i].distance + targetMeters
            if endDistance > total { break }
            if j < i { j = i }
            while samples[j].distance < endDistance { j += 1 }
            let endTime = interpolatedTime(at: endDistance, lower: j - 1, upper: j, in: samples)
            best = min(best, endTime - samples[i].time)
        }

        // End at sample k; interpolate where the window started.
        var s = 0
        for k in samples.indices {
            let startDistance = samples[k].distance - targetMeters
            if startDistance < 0 { continue }
            while s + 1 <= k, samples[s + 1].distance <= startDistance { s += 1 }
            let startTime = interpolatedTime(at: startDistance, lower: s, upper: s + 1, in: samples)
            best = min(best, samples[k].time - startTime)
        }

        return best.isFinite && best > 0 ? best : nil
    }

    private static func interpolatedTime(
        at distance: Double,
        lower: Int,
        upper: Int,
        in samples: [RouteSample]
    ) -> TimeInterval {
        guard lower >= 0 else { return samples[upper].time }
        guard upper < samples.count else { return samples[lower].time }
        let a = samples[lower]
        let b = samples[upper]
        let span = b.distance - a.distance
        guard span > 0 else { return b.time }
        return a.time + (b.time - a.time) * (distance - a.distance) / span
    }

    // MARK: - Splits

    /// Splits in route order. A split closes at the first point where its accumulated
    /// distance reaches `segmentDistanceMeters`; the rest becomes a final partial split.
    /// Index ranges refer to positions in `route` as passed in.
    static func splits(route: [CLLocation], segmentDistanceMeters: Double) -> [RouteSplit] {
        guard segmentDistanceMeters.isFinite, segmentDistanceMeters > 0,
              route.count > 1 else { return [] }

        var splits: [RouteSplit] = []
        var startIndex = 0
        var segmentDistance = 0.0
        var segmentTime: TimeInterval = 0

        for index in 1..<route.count {
            let previous = route[index - 1]
            let current = route[index]
            let step = current.distance(from: previous)
            let elapsed = current.timestamp.timeIntervalSince(previous.timestamp)
            if step.isFinite { segmentDistance += step }
            if elapsed.isFinite, elapsed > 0 { segmentTime += elapsed }

            if segmentDistance >= segmentDistanceMeters {
                splits.append(RouteSplit(
                    number: splits.count + 1,
                    distance: segmentDistance,
                    duration: segmentTime,
                    indexRange: startIndex...index
                ))
                startIndex = index
                segmentDistance = 0
                segmentTime = 0
            }
        }

        if segmentDistance > 0 {
            splits.append(RouteSplit(
                number: splits.count + 1,
                distance: segmentDistance,
                duration: segmentTime,
                indexRange: startIndex...(route.count - 1)
            ))
        }
        return splits
    }
}

// MARK: - Backfill cursor

/// Position of the last fully processed run, ordered by `(date, uuidString)`.
struct BackfillCursor: Equatable {
    let date: Date
    let uuidString: String

    /// True when `(date, uuidString)` sorts strictly after this cursor.
    func precedes(date otherDate: Date, uuidString otherUUID: String) -> Bool {
        if otherDate != date { return otherDate > date }
        return otherUUID > uuidString
    }

    /// Items sorted by `(date, uuidString)` and kept only when strictly after `cursor`.
    static func pending<T>(
        _ items: [T],
        after cursor: BackfillCursor?,
        date: (T) -> Date,
        uuidString: (T) -> String
    ) -> [T] {
        let sorted = items.sorted { lhs, rhs in
            let lhsDate = date(lhs)
            let rhsDate = date(rhs)
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            return uuidString(lhs) < uuidString(rhs)
        }
        guard let cursor else { return sorted }
        return sorted.filter { cursor.precedes(date: date($0), uuidString: uuidString($0)) }
    }
}
