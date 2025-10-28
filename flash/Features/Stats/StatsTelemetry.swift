import Foundation
import os

struct StatsTelemetry {
    private let logger = Logger(subsystem: "app.flash.stats", category: "StatsView")

    func recordFirstPaint(milliseconds: Double) {
        logger.log("stats.hr_first_paint_ms=\(milliseconds, format: .fixed(precision: 2))")
    }

    func recordIngestLatency(milliseconds: Double) {
        logger.log("stats.hr_ingest_to_ui_ms=\(milliseconds, format: .fixed(precision: 2))")
    }

    func recordDroppedPoints(_ count: Int) {
        logger.log("stats.hr_points_dropped=\(count)")
    }
}
