import Foundation

enum RunSummaryAdapter {
    static func runningData(from summary: CachedRunSummary) -> RunningData {
        let paceMinutesPerKilometer: Double
        if summary.distance > 0, summary.duration > 0 {
            paceMinutesPerKilometer = (summary.duration / 60) / (summary.distance / 1_000)
        } else {
            paceMinutesPerKilometer = 0
        }
        let formattedDuration = RunUnitPresentation.durationText(summary.duration)

        return RunningData(
            date: summary.date,
            distance: summary.distance,
            cadence: 0,
            power: 0,
            pace: paceMinutesPerKilometer,
            formattedPace: paceText(paceMinutesPerKilometer),
            heartRate: summary.avgHR ?? 0,
            strideLength: 0,
            verticalOscillation: 0,
            groundContactTime: 0,
            duration: summary.duration,
            formattedDuration: formattedDuration,
            elevation: summary.elevationGain,
            activeCalories: summary.calories,
            route: [],
            formatDuration: formattedDuration,
            pacePerKM: [],
            heartRateData: [],
            cadenceData: [],
            heartRateZones: [],
            healthKitUUID: summary.healthKitUUID
        )
    }

    private static func paceText(_ paceMinutesPerKilometer: Double) -> String {
        guard paceMinutesPerKilometer.isFinite, paceMinutesPerKilometer > 0 else {
            return "N/A"
        }
        let totalSeconds = Int((paceMinutesPerKilometer * 60).rounded())
        return String(format: "%d:%02d/km", totalSeconds / 60, totalSeconds % 60)
    }
}
