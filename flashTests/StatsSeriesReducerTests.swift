import XCTest
@testable import flash

final class StatsSeriesReducerTests: XCTestCase {
    func testDownsamplingPreservesExtrema() async {
        let reducer = StatsSeriesReducer<HeartRateDataPoint>(downsampleThreshold: 10, downsampleLimit: 5)
        let samples = stride(from: 0, to: 20, by: 1).map { index -> HeartRateDataPoint in
            HeartRateDataPoint(
                timestamp: Date(timeIntervalSinceReferenceDate: TimeInterval(index)),
                heartRate: Double(120 + index),
                relativeTime: TimeInterval(index)
            )
        }
        let update = await reducer.reset(with: samples)
        XCTAssertEqual(update.displaySamples.count, 5)
        let displayedValues = update.displaySamples.map(\.heartRate)
        XCTAssertTrue(displayedValues.contains(samples.map(\.heartRate).min()!))
        XCTAssertTrue(displayedValues.contains(samples.map(\.heartRate).max()!))
    }

    func testIncrementalStatsUpdate() async {
        let reducer = StatsSeriesReducer<HeartRateDataPoint>(downsampleThreshold: 10, downsampleLimit: 10)
        let initial = [80, 85, 90].enumerated().map { index, value in
            HeartRateDataPoint(
                timestamp: Date(timeIntervalSinceReferenceDate: TimeInterval(index)),
                heartRate: Double(value),
                relativeTime: TimeInterval(index)
            )
        }
        let initialUpdate = await reducer.reset(with: initial)
        XCTAssertEqual(initialUpdate.stats?.count, 3)
        XCTAssertEqual(initialUpdate.stats?.average, (80 + 85 + 90).double / 3, accuracy: 0.001)

        let newSample = HeartRateDataPoint(
            timestamp: Date(timeIntervalSinceReferenceDate: 3),
            heartRate: 95,
            relativeTime: 3
        )
        let secondUpdate = await reducer.ingest([newSample])
        XCTAssertEqual(secondUpdate.stats?.count, 4)
        XCTAssertEqual(secondUpdate.stats?.average, (80 + 85 + 90 + 95).double / 4, accuracy: 0.001)
        XCTAssertEqual(secondUpdate.displaySamples.count, 4)
    }

    func testOutOfOrderTimestamps() async {
        let reducer = StatsSeriesReducer<HeartRateDataPoint>(downsampleThreshold: 10, downsampleLimit: 10)
        let baseSamples = [0, 10, 20].map { value -> HeartRateDataPoint in
            HeartRateDataPoint(
                timestamp: Date(timeIntervalSinceReferenceDate: TimeInterval(value)),
                heartRate: Double(150 + value),
                relativeTime: TimeInterval(value)
            )
        }
        _ = await reducer.reset(with: baseSamples)

        let outOfOrderSample = HeartRateDataPoint(
            timestamp: Date(timeIntervalSinceReferenceDate: 5),
            heartRate: 200,
            relativeTime: 5
        )
        let update = await reducer.ingest([outOfOrderSample])
        XCTAssertEqual(update.displaySamples.count, 4)
        let times = update.displaySamples.map(\.relativeTime)
        XCTAssertEqual(times, [0, 5, 10, 20])
        XCTAssertTrue(update.displaySamples.contains(where: { $0.heartRate == 200 }))
    }
}

private extension BinaryInteger {
    var double: Double { Double(self) }
}
