import Foundation

/// One run's input to training load. Plain values only.
struct TrainingLoadRun: Equatable {
    let date: Date
    let durationSeconds: Double
    let averageHR: Double?
}

/// Heart-rate settings for TRIMP. `isFemale == nil` means the TRIMP sex is not set.
struct TrainingLoadSettings: Equatable {
    let maxHR: Double
    let restingHR: Double
    let isFemale: Bool?
}

struct RunLoad: Equatable {
    let load: Double
    /// True when the load is duration-only because HR or HR settings were missing.
    let isEstimated: Bool
}

struct DailyLoadPoint: Equatable {
    let day: Date
    let load: Double
    let ctl: Double    // fitness: 42-day exponentially weighted load
    let atl: Double    // fatigue: 7-day exponentially weighted load
    let form: Double   // ctl - atl
    let isEstimated: Bool
}

/// Rule-based status from form. Thresholds are fixed so the label is predictable.
enum TrainingLoadStatus: Equatable {
    case fresh      // form > 5
    case balanced   // -10 ... 5
    case fatigued   // form < -10

    init(form: Double) {
        if form > 5 {
            self = .fresh
        } else if form < -10 {
            self = .fatigued
        } else {
            self = .balanced
        }
    }

    var title: String {
        switch self {
        case .fresh: "Fresh"
        case .balanced: "Balanced"
        case .fatigued: "Fatigued"
        }
    }
}

/// Banister TRIMP and fitness/fatigue/form. Deterministic math, no HealthKit or SwiftData.
enum TrainingLoadEngine {
    static let fitnessDays = 42.0
    static let fatigueDays = 7.0

    /// TRIMP for one run. Falls back to duration in minutes, marked estimated, when average HR
    /// is missing, the TRIMP sex is not set, or max HR is not above resting HR.
    static func load(for run: TrainingLoadRun, settings: TrainingLoadSettings) -> RunLoad {
        guard run.durationSeconds.isFinite, run.durationSeconds > 0 else {
            return RunLoad(load: 0, isEstimated: false)
        }
        let minutes = run.durationSeconds / 60

        guard let isFemale = settings.isFemale,
              let averageHR = run.averageHR,
              averageHR.isFinite, averageHR > 0,
              settings.maxHR.isFinite, settings.restingHR.isFinite,
              settings.maxHR > settings.restingHR else {
            return RunLoad(load: minutes, isEstimated: true)
        }

        let reserve = (averageHR - settings.restingHR) / (settings.maxHR - settings.restingHR)
        let hrr = min(max(reserve, 0), 1)
        let coefficient = isFemale ? 0.86 : 0.64
        let exponent = isFemale ? 1.67 : 1.92
        let trimp = minutes * hrr * coefficient * exp(exponent * hrr)
        guard trimp.isFinite else { return RunLoad(load: minutes, isEstimated: true) }
        return RunLoad(load: trimp, isEstimated: false)
    }

    /// Every calendar day from the first run's day through `today`, rest days included.
    /// Fitness and fatigue start at zero before the first run.
    static func dailySeries(
        runs: [TrainingLoadRun],
        settings: TrainingLoadSettings,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> [DailyLoadPoint] {
        guard let firstDate = runs.map(\.date).min() else { return [] }

        var loadByDay: [Date: Double] = [:]
        var estimatedDays: Set<Date> = []
        for run in runs {
            let day = calendar.startOfDay(for: run.date)
            let runLoad = load(for: run, settings: settings)
            loadByDay[day, default: 0] += runLoad.load
            if runLoad.isEstimated {
                estimatedDays.insert(day)
            }
        }

        let lastRunDay = calendar.startOfDay(for: runs.map(\.date).max() ?? firstDate)
        let endDay = max(calendar.startOfDay(for: today), lastRunDay)
        var day = calendar.startOfDay(for: firstDate)
        var ctl = 0.0
        var atl = 0.0
        var points: [DailyLoadPoint] = []

        // Not `<=`/`>=`: those Date operators are weak-linked and crash on iOS 27.2 beta.
        while !(endDay < day) {
            let load = loadByDay[day] ?? 0
            ctl += (load - ctl) / fitnessDays
            atl += (load - atl) / fatigueDays
            points.append(DailyLoadPoint(
                day: day,
                load: load,
                ctl: ctl,
                atl: atl,
                form: ctl - atl,
                isEstimated: estimatedDays.contains(day)
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = calendar.startOfDay(for: next)
        }
        return points
    }
}
