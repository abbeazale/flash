import Foundation

protocol TimeSeriesSample: Sendable {
    var timestamp: Date { get }
    var relativeTime: TimeInterval { get }
    var value: Double { get }
}

extension HeartRateDataPoint: TimeSeriesSample, Identifiable, Sendable {
    var id: String { "hr-\(timestamp.timeIntervalSince1970)-\(relativeTime)" }
    var value: Double { heartRate }
}

extension CadenceDataPoint: TimeSeriesSample, Identifiable, Sendable {
    var id: String { "cad-\(timestamp.timeIntervalSince1970)-\(relativeTime)" }
    var value: Double { cadence }
}

struct SeriesStats: Equatable, Sendable {
    private(set) var min: Double
    private(set) var max: Double
    private(set) var sum: Double
    private(set) var count: Int

    init?(values: [Double]) {
        guard let first = values.first else { return nil }
        min = first
        max = first
        sum = first
        count = 1
        if values.count > 1 {
            add(values: values.dropFirst())
        }
    }

    var average: Double {
        guard count > 0 else { return 0 }
        return sum / Double(count)
    }

    mutating func add<S: Sequence>(values: S) where S.Element == Double {
        for value in values {
            add(value)
        }
    }

    mutating func add(_ value: Double) {
        if count == 0 {
            min = value
            max = value
            sum = value
            count = 1
            return
        }
        min = Swift.min(min, value)
        max = Swift.max(max, value)
        sum += value
        count += 1
    }
}

struct SeriesUpdate<Sample: TimeSeriesSample>: Sendable {
    let displaySamples: [Sample]
    let stats: SeriesStats?
    let droppedPoints: Int
}

enum Downsampler {
    static func downsampleIfNeeded<Sample: TimeSeriesSample>(
        samples: [Sample],
        threshold: Int,
        limit: Int
    ) -> ([Sample], Int) {
        guard samples.count > threshold, limit > 1 else {
            return (samples, 0)
        }

        let cappedLimit = max(2, limit)
        let lastIndex = samples.count - 1

        var indices = Set<Int>()
        indices.insert(0)
        indices.insert(lastIndex)

        let minIndex = samples.enumerated().min(by: { $0.element.value < $1.element.value })?.offset
        let maxIndex = samples.enumerated().max(by: { $0.element.value < $1.element.value })?.offset

        if let minIndex { indices.insert(minIndex) }
        if let maxIndex { indices.insert(maxIndex) }

        let step = Double(samples.count - 1) / Double(cappedLimit - 1)
        if step.isFinite {
            for bucket in 0..<cappedLimit {
                let index = Int(round(Double(bucket) * step))
                indices.insert(min(index, lastIndex))
            }
        }

        let required = Set([0, lastIndex, minIndex, maxIndex].compactMap { $0 })
        var sortedIndices = indices.sorted()
        while sortedIndices.count > cappedLimit {
            var candidatePosition: Int?
            var smallestDistance = Double.greatestFiniteMagnitude

            for (position, index) in sortedIndices.enumerated() {
                if required.contains(index) { continue }
                let previous = position > 0 ? sortedIndices[position - 1] : nil
                let next = position < sortedIndices.count - 1 ? sortedIndices[position + 1] : nil

                let distance: Double
                switch (previous, next) {
                case let (prev?, next?):
                    distance = Double(next - prev)
                case let (prev?, nil):
                    distance = Double(index - prev)
                case let (nil, next?):
                    distance = Double(next - index)
                default:
                    distance = 0
                }

                if distance < smallestDistance {
                    smallestDistance = distance
                    candidatePosition = position
                }
            }

            if let candidatePosition {
                sortedIndices.remove(at: candidatePosition)
            } else {
                break
            }
        }

        let result = sortedIndices.map { samples[$0] }.sorted { $0.timestamp < $1.timestamp }
        let dropped = samples.count - result.count
        return (result, max(0, dropped))
    }
}

actor StatsSeriesReducer<Sample: TimeSeriesSample> {
    private var allSamples: [Sample] = []
    private var stats: SeriesStats?
    private let downsampleThreshold: Int
    private let downsampleLimit: Int

    init(downsampleThreshold: Int, downsampleLimit: Int) {
        self.downsampleThreshold = downsampleThreshold
        self.downsampleLimit = downsampleLimit
    }

    func reset(with samples: [Sample]) -> SeriesUpdate<Sample> {
        allSamples = samples.sorted { $0.timestamp < $1.timestamp }
        stats = SeriesStats(values: allSamples.map(\._value))
        return currentUpdate()
    }

    func ingest(_ samples: [Sample]) -> SeriesUpdate<Sample> {
        guard !samples.isEmpty else { return currentUpdate() }
        let sortedBatch = samples.sorted { $0.timestamp < $1.timestamp }
        if allSamples.isEmpty {
            allSamples = sortedBatch
            stats = SeriesStats(values: sortedBatch.map(\._value))
            return currentUpdate()
        }

        var merged: [Sample] = []
        merged.reserveCapacity(allSamples.count + sortedBatch.count)
        var additions: [Sample] = []

        var existingIndex = 0
        var newIndex = 0

        while existingIndex < allSamples.count || newIndex < sortedBatch.count {
            if existingIndex == allSamples.count {
                let sample = sortedBatch[newIndex]
                merged.append(sample)
                additions.append(sample)
                newIndex += 1
            } else if newIndex == sortedBatch.count {
                merged.append(allSamples[existingIndex])
                existingIndex += 1
            } else {
                let existingSample = allSamples[existingIndex]
                let newSample = sortedBatch[newIndex]

                if newSample.timestamp < existingSample.timestamp {
                    merged.append(newSample)
                    additions.append(newSample)
                    newIndex += 1
                } else if newSample.timestamp == existingSample.timestamp {
                    // Keep the existing data point to avoid recalculating stats
                    merged.append(existingSample)
                    newIndex += 1
                    existingIndex += 1
                } else {
                    merged.append(existingSample)
                    existingIndex += 1
                }
            }
        }

        allSamples = merged

        if !additions.isEmpty {
            if stats == nil {
                stats = SeriesStats(values: additions.map(\._value))
            } else {
                stats?.add(values: additions.map(\._value))
            }
        }

        return currentUpdate()
    }

    func currentUpdate() -> SeriesUpdate<Sample> {
        guard !allSamples.isEmpty else {
            return SeriesUpdate(displaySamples: [], stats: nil, droppedPoints: 0)
        }

        let (display, dropped) = Downsampler.downsampleIfNeeded(
            samples: allSamples,
            threshold: downsampleThreshold,
            limit: downsampleLimit
        )
        return SeriesUpdate(displaySamples: display, stats: stats, droppedPoints: dropped)
    }
}

private extension TimeSeriesSample {
    var _value: Double { value }
}
