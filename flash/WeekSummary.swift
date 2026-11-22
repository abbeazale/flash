//
//  WeekSummary.swift
//  flash
//

import Foundation

extension Calendar {
    /// The user's calendar with weeks that start on Monday and end on Sunday.
    static var mondayFirst: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }
}

extension Date {
    /// Midnight on the Monday of this date's week.
    func startOfWeek(using calendar: Calendar = .mondayFirst) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: self)?.start ?? calendar.startOfDay(for: self)
    }
}

/// One run, with only the fields the weekly summary needs.
struct WeekRun: Equatable {
    let date: Date
    let distanceMeters: Double
    let duration: TimeInterval
}

/// Distance and time for a week or for one day.
struct WeekTotals: Equatable {
    let kilometers: Double
    let duration: TimeInterval

    /// Minutes per kilometer. 0 when there is no distance.
    var averagePace: Double {
        kilometers > 0 ? duration / 60 / kilometers : 0
    }

    /// Time as h:mm:ss.
    var formattedDuration: String {
        let seconds = Int(duration)
        return String(format: "%0d:%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60)
    }
}

/// Totals and per-day distance for one Monday-to-Sunday week.
struct WeekSummary: Codable, Equatable {
    let weekStart: Date
    let totalKilometers: Double
    let totalDuration: TimeInterval
    /// Minutes per kilometer. 0 when the week has no distance.
    let averagePace: Double
    /// Kilometers ran on Monday through Sunday.
    let dailyKilometers: [Double]
    /// Run time on Monday through Sunday.
    let dailyDurations: [TimeInterval]

    static func empty(weekStart: Date) -> WeekSummary {
        WeekSummary(
            weekStart: weekStart,
            totalKilometers: 0,
            totalDuration: 0,
            averagePace: 0,
            dailyKilometers: Array(repeating: 0, count: 7),
            dailyDurations: Array(repeating: 0, count: 7)
        )
    }

    /// Adds up the runs that start in the week that begins at `weekStart`.
    /// Runs outside that week are ignored.
    static func make(
        weekStart: Date,
        runs: [WeekRun],
        calendar: Calendar = .mondayFirst
    ) -> WeekSummary {
        var dailyKilometers = Array(repeating: 0.0, count: 7)
        var dailyDurations = Array(repeating: 0.0, count: 7)
        var totalMeters = 0.0
        var totalDuration: TimeInterval = 0

        for run in runs {
            guard let day = calendar.dateComponents(
                [.day],
                from: weekStart,
                to: calendar.startOfDay(for: run.date)
            ).day, (0..<7).contains(day) else { continue }

            dailyKilometers[day] += run.distanceMeters / 1_000
            dailyDurations[day] += run.duration
            totalMeters += run.distanceMeters
            totalDuration += run.duration
        }

        let totalKilometers = totalMeters / 1_000
        return WeekSummary(
            weekStart: weekStart,
            totalKilometers: totalKilometers,
            totalDuration: totalDuration,
            averagePace: totalKilometers > 0 ? totalDuration / 60 / totalKilometers : 0,
            dailyKilometers: dailyKilometers,
            dailyDurations: dailyDurations
        )
    }

    /// Totals for the whole week.
    var totals: WeekTotals {
        WeekTotals(kilometers: totalKilometers, duration: totalDuration)
    }

    /// Totals for one day. 0 is Monday, 6 is Sunday.
    func totals(forDay index: Int) -> WeekTotals {
        guard dailyKilometers.indices.contains(index),
              dailyDurations.indices.contains(index) else {
            return WeekTotals(kilometers: 0, duration: 0)
        }
        return WeekTotals(kilometers: dailyKilometers[index], duration: dailyDurations[index])
    }

    /// Monday through Sunday of this week.
    func days(calendar: Calendar = .mondayFirst) -> [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    /// The first moment after Sunday ends.
    func weekEnd(calendar: Calendar = .mondayFirst) -> Date {
        calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart.addingTimeInterval(7 * 86_400)
    }

    /// Total time as h:mm:ss.
    var formattedDuration: String { totals.formattedDuration }

    /// Number of whole weeks between the week of `earlier` and the week of `later`.
    static func weeksBetween(
        _ earlier: Date,
        and later: Date,
        calendar: Calendar = .mondayFirst
    ) -> Int {
        let days = calendar.dateComponents(
            [.day],
            from: earlier.startOfWeek(using: calendar),
            to: later.startOfWeek(using: calendar)
        ).day ?? 0
        return max(0, Int((Double(days) / 7).rounded()))
    }
}
