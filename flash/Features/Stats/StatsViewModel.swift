import Foundation

final class StatsViewModel: ObservableObject {
    @Published private(set) var heartRateSeries: [HeartRateDataPoint] = []
    @Published private(set) var heartRateStats: SeriesStats?
    @Published private(set) var heartRateMessage: String?

    @Published private(set) var cadenceSeries: [CadenceDataPoint] = []
    @Published private(set) var cadenceStats: SeriesStats?
    @Published private(set) var cadenceMessage: String?

    private let run: RunningData
    private let sampleProvider: StatsSampleProviding
    private let telemetry: StatsTelemetry
    private let heartRateReducer = StatsSeriesReducer<HeartRateDataPoint>(downsampleThreshold: 5000, downsampleLimit: 2000)
    private let cadenceReducer = StatsSeriesReducer<CadenceDataPoint>(downsampleThreshold: 4000, downsampleLimit: 2000)

    private var loadTask: Task<Void, Never>?
    private var heartRateTask: Task<Void, Never>?
    private var cadenceTask: Task<Void, Never>?
    private var appearTime: DispatchTime?
    private var firstHeartRatePaintRecorded = false

    init(run: RunningData, sampleProvider: StatsSampleProviding = DefaultStatsSampleProvider(), telemetry: StatsTelemetry = StatsTelemetry()) {
        self.run = run
        self.sampleProvider = sampleProvider
        self.telemetry = telemetry
    }

    @MainActor
    func onAppear() {
        guard loadTask == nil else { return }
        appearTime = DispatchTime.now()
        loadTask = Task { [weak self] in
            guard let self else { return }
            await self.prewarmData()
            await self.startStreams()
        }
    }

    @MainActor
    func onDisappear() {
        loadTask?.cancel()
        loadTask = nil
        heartRateTask?.cancel()
        heartRateTask = nil
        cadenceTask?.cancel()
        cadenceTask = nil
    }

    private func prewarmData() async {
        let prewarmWindow = min(max(run.duration, 30), 120)

        let heartRatePrewarm = await sampleProvider.prewarmHeartRate(for: run, last: prewarmWindow)
        guard !Task.isCancelled else { return }
        if !heartRatePrewarm.isEmpty {
            let update = await heartRateReducer.reset(with: heartRatePrewarm)
            await applyHeartRateUpdate(update, receivedAt: Date())
        } else {
            await MainActor.run { [weak self] in
                self?.heartRateMessage = "No heart rate data available"
            }
        }

        let cadencePrewarm = await sampleProvider.prewarmCadence(for: run, last: prewarmWindow)
        guard !Task.isCancelled else { return }
        if !cadencePrewarm.isEmpty {
            let update = await cadenceReducer.reset(with: cadencePrewarm)
            await applyCadenceUpdate(update)
        } else {
            await MainActor.run { [weak self] in
                self?.cadenceMessage = "Not enough cadence data for this run."
            }
        }
    }

    private func startStreams() async {
        heartRateTask?.cancel()
        heartRateTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.consumeHeartRateStream()
        }

        cadenceTask?.cancel()
        cadenceTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.consumeCadenceStream()
        }
    }

    private func consumeHeartRateStream() async {
        let stream = sampleProvider.heartRateStream(for: run)
        var pending: [HeartRateDataPoint] = []
        var lastFlush = ContinuousClock.now
        for await batch in stream {
            if Task.isCancelled { break }
            pending.append(contentsOf: batch.samples)
            let now = ContinuousClock.now
            if lastFlush.duration(to: now) >= .milliseconds(350) {
                let samplesToApply = pending
                pending.removeAll(keepingCapacity: true)
                lastFlush = now
                await ingestHeartRateSamples(samplesToApply, receivedAt: batch.receivedAt)
            }
        }
        if !pending.isEmpty {
            await ingestHeartRateSamples(pending, receivedAt: Date())
        }
    }

    private func consumeCadenceStream() async {
        let stream = sampleProvider.cadenceStream(for: run)
        var pending: [CadenceDataPoint] = []
        var lastFlush = ContinuousClock.now
        for await batch in stream {
            if Task.isCancelled { break }
            pending.append(contentsOf: batch.samples)
            let now = ContinuousClock.now
            if lastFlush.duration(to: now) >= .milliseconds(350) {
                let samplesToApply = pending
                pending.removeAll(keepingCapacity: true)
                lastFlush = now
                await ingestCadenceSamples(samplesToApply)
            }
        }
        if !pending.isEmpty {
            await ingestCadenceSamples(pending)
        }
    }

    private func ingestHeartRateSamples(_ samples: [HeartRateDataPoint], receivedAt: Date) async {
        guard !samples.isEmpty else { return }
        let update = await heartRateReducer.ingest(samples)
        await applyHeartRateUpdate(update, receivedAt: receivedAt)
    }

    private func ingestCadenceSamples(_ samples: [CadenceDataPoint]) async {
        guard !samples.isEmpty else { return }
        let update = await cadenceReducer.ingest(samples)
        await applyCadenceUpdate(update)
    }

    private func applyHeartRateUpdate(_ update: SeriesUpdate<HeartRateDataPoint>, receivedAt: Date) async {
        await MainActor.run { [weak self] in
            guard let self else { return }
            self.heartRateSeries.overwrite(with: update.displaySamples)
            self.heartRateStats = update.stats
            self.heartRateMessage = update.displaySamples.isEmpty ? "No heart rate data available" : nil

            let latencyMs = Date().timeIntervalSince(receivedAt) * 1000
            self.telemetry.recordIngestLatency(milliseconds: latencyMs)

            if let appearTime = self.appearTime, !self.firstHeartRatePaintRecorded, !update.displaySamples.isEmpty {
                let now = DispatchTime.now()
                let delta = Double(now.uptimeNanoseconds - appearTime.uptimeNanoseconds) / 1_000_000
                self.telemetry.recordFirstPaint(milliseconds: delta)
                self.firstHeartRatePaintRecorded = true
            }

            if update.droppedPoints > 0 {
                self.telemetry.recordDroppedPoints(update.droppedPoints)
            }
        }
    }

    private func applyCadenceUpdate(_ update: SeriesUpdate<CadenceDataPoint>) async {
        await MainActor.run { [weak self] in
            guard let self else { return }
            self.cadenceSeries.overwrite(with: update.displaySamples)
            self.cadenceStats = update.stats
            if update.displaySamples.count < 3 {
                self.cadenceMessage = "Not enough cadence data for this run."
            } else {
                self.cadenceMessage = nil
            }
        }
    }
}

private extension Array where Element: TimeSeriesSample {
    mutating func overwrite(with newElements: [Element]) {
        if count == newElements.count {
            withUnsafeMutableBufferPointer { destination in
                guard let destBase = destination.baseAddress else { return }
                newElements.withUnsafeBufferPointer { source in
                    guard let srcBase = source.baseAddress else { return }
                    destBase.update(from: srcBase, count: destination.count)
                }
            }
        } else {
            removeAll(keepingCapacity: true)
            append(contentsOf: newElements)
        }
    }
}
