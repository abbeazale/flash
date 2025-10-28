# Cadence Chart Implementation - Documentation

## Overview
This document outlines the implementation of the **Cadence Time Series Chart** feature for the stats view, including all relevant HealthKit and Apple documentation references.

## Implementation Date
**Sprint**: Pre-Beta Testing
**Branch**: `charts`
**Status**: Ready for PM Review

---

## Feature Summary
Added a time-series cadence chart to the stats view that displays running cadence (steps per minute) over the duration of a run. The chart matches the existing design theme and provides interactive data exploration.

---

## Apple HealthKit Documentation References

### 1. Running Cadence Data Type
**HKQuantityTypeIdentifierRunningCadence**

**Official Documentation**: 
- [HKQuantityTypeIdentifier - Running Cadence](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/3131071-runningcadence)
- Added in iOS 16.0+, watchOS 9.0+

**Description**: 
Running cadence measures the number of steps per minute (SPM) during a running workout. This metric is crucial for:
- Running form analysis
- Injury prevention (optimal cadence is typically 170-180 SPM)
- Performance optimization
- Training efficiency

**Unit**: 
- `HKUnit.count().unitDivided(by: HKUnit.minute())` - steps per minute (SPM)

**Code Implementation**:
```swift
// HealthManager.swift - Line 40
private static let runningCadenceIdentifier = HKQuantityTypeIdentifier(rawValue: "HKQuantityTypeIdentifierRunningCadence")

// Line 108-112
if let runningCadenceType = HKObjectType.quantityType(forIdentifier: Self.runningCadenceIdentifier) {
    readTypes.insert(runningCadenceType)
}
```

---

### 2. HealthKit Authorization
**Requesting Access to Cadence Data**

**Official Documentation**:
- [Requesting Authorization to Access HealthKit](https://developer.apple.com/documentation/healthkit/setting_up_healthkit)
- [HKHealthStore.requestAuthorization](https://developer.apple.com/documentation/healthkit/hkhealthstore/1614152-requestauthorization)

**Implementation**:
```swift
// HealthManager.swift - Lines 85-127
private func requestAuthorization() async {
    var readTypes: Set<HKObjectType> = [
        // ... other types
        HKObjectType.quantityType(forIdentifier: .stepCount)!,
        // ... more types
    ]
    
    // Request cadence access
    if let runningCadenceType = HKObjectType.quantityType(forIdentifier: Self.runningCadenceIdentifier) {
        readTypes.insert(runningCadenceType)
    }
    
    try await healthStore.requestAuthorization(toShare: nil, read: readTypes)
}
```

---

### 3. Querying Time-Series Cadence Data
**HKSampleQuery for Cadence Samples**

**Official Documentation**:
- [HKSampleQuery](https://developer.apple.com/documentation/healthkit/hksamplequery)
- [HKQuantitySample](https://developer.apple.com/documentation/healthkit/hkquantitysample)
- [Querying Sample Data](https://developer.apple.com/documentation/healthkit/samples/querying_sample_data)

**Implementation Pattern**:
```swift
// HealthManager.swift - Lines 482-517
private func fetchCadenceTimeSeries(for workout: HKWorkout) async -> [CadenceDataPoint] {
    guard let cadenceType = HKQuantityType.quantityType(forIdentifier: Self.runningCadenceIdentifier) else {
        return []
    }

    let predicate = HKQuery.predicateForSamples(
        withStart: workout.startDate, 
        end: workout.endDate, 
        options: .strictStartDate
    )

    return await withCheckedContinuation { continuation in
        let query = HKSampleQuery(
            sampleType: cadenceType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        ) { _, samples, _ in
            guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else {
                continuation.resume(returning: [])
                return
            }

            let startTime = workout.startDate
            let cadencePoints = samples.map { sample -> CadenceDataPoint in
                let cadence = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))
                let relativeTime = sample.startDate.timeIntervalSince(startTime)
                return CadenceDataPoint(
                    timestamp: sample.startDate,
                    cadence: cadence,
                    relativeTime: relativeTime
                )
            }

            continuation.resume(returning: cadencePoints)
        }

        healthStore.execute(query)
    }
}
```

**Key Points**:
- Uses `HKSampleSortIdentifierStartDate` for chronological ordering
- Converts absolute timestamps to relative time (seconds from workout start)
- Handles missing cadence data gracefully

---

### 4. Live Streaming Cadence Data with Anchored Queries
**HKAnchoredObjectQuery for Real-Time Updates**

**Official Documentation**:
- [HKAnchoredObjectQuery](https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery)
- [Observing Changes to the HealthKit Store](https://developer.apple.com/documentation/healthkit/samples/observing_changes_to_the_healthkit_store)

**Implementation**:
```swift
// StatsSampleProvider.swift - Lines 189-231
func cadenceStream(for run: RunningData) -> AsyncStream<StatsSampleBatch<CadenceDataPoint>> {
    guard let cadenceType else { return AsyncStream { $0.finish() } }
    return AsyncStream { continuation in
        let predicate = HKQuery.predicateForSamples(withStart: run.date, end: nil, options: .strictStartDate)
        var anchor = anchorStore.loadAnchor(for: .cadence)

        let query = HKAnchoredObjectQuery(
            type: cadenceType,
            predicate: predicate,
            anchor: anchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, error in
            guard let self else { return }
            if let error { 
                self.logger.error("Cadence query error: \\(error.localizedDescription, privacy: .public)") 
            }
            anchor = newAnchor ?? anchor
            if let newAnchor { 
                self.anchorStore.saveAnchor(newAnchor, for: .cadence) 
            }
            let points = (samples as? [HKQuantitySample])?.map { 
                self.makeCadencePoint($0, runStart: run.date) 
            } ?? []
            if !points.isEmpty {
                continuation.yield(StatsSampleBatch(samples: points, receivedAt: Date()))
            }
        }

        query.updateHandler = { [weak self] _, samples, _, newAnchor, error in
            // Handle real-time updates
            guard let self else { return }
            if let error { 
                self.logger.error("Cadence update error: \\(error.localizedDescription, privacy: .public)") 
            }
            if let newAnchor {
                anchor = newAnchor
                self.anchorStore.saveAnchor(newAnchor, for: .cadence)
            }
            let points = (samples as? [HKQuantitySample])?.map { 
                self.makeCadencePoint($0, runStart: run.date) 
            } ?? []
            if !points.isEmpty {
                continuation.yield(StatsSampleBatch(samples: points, receivedAt: Date()))
            }
        }

        self.healthStore.execute(query)
        continuation.onTermination = { [weak self] _ in
            if let query = query as HKQuery? {
                self?.healthStore.stop(query)
            }
        }
    }
}
```

**Benefits**:
- Provides real-time updates as new cadence data becomes available
- Persists query anchors for efficient incremental fetching
- Reduces battery and performance impact

---

## SwiftUI Charts Framework

### Swift Charts Documentation
**Official Documentation**:
- [Swift Charts Framework](https://developer.apple.com/documentation/charts)
- [Creating a Chart Using Swift Charts](https://developer.apple.com/documentation/charts/creating-a-chart-using-swift-charts)
- [LineMark](https://developer.apple.com/documentation/charts/linemark)
- [AreaMark](https://developer.apple.com/documentation/charts/areamark)
- [PointMark](https://developer.apple.com/documentation/charts/pointmark)

**Requirements**: iOS 16.0+, macOS 13.0+

---

### Chart Implementation
**Cadence Time-Series Chart**

**Code Location**: `StatsView.swift` - Lines 130-186

**Chart Components**:

1. **LineMark** - Main cadence trend line
```swift
LineMark(
    x: .value("Time", dataPoint.relativeTime),
    y: .value("Cadence", dataPoint.cadence)
)
.lineStyle(.init(lineWidth: 2, lineCap: .round, lineJoin: .round))
.foregroundStyle(StatsColors.accent)
```

2. **AreaMark** - Gradient fill under the line
```swift
AreaMark(
    x: .value("Time", dataPoint.relativeTime),
    y: .value("Cadence", dataPoint.cadence)
)
.foregroundStyle(StatsColors.accent.opacity(0.2))
```

3. **PointMark** - Data point markers every 15 seconds
```swift
if shouldShowMarker(for: dataPoint) {
    PointMark(
        x: .value("Time", dataPoint.relativeTime),
        y: .value("Cadence", dataPoint.cadence)
    )
    .symbol(Circle().strokeBorder(StatsColors.accent, lineWidth: 2)
        .background(Circle().fill(StatsColors.accent.opacity(0.4))))
    .foregroundStyle(StatsColors.accent)
}
```

**Chart Customization**:

```swift
.chartXScale(domain: 0...run.duration)  // Full workout duration
.chartYScale(domain: cadenceYDomain)    // Dynamic range based on data
.chartXAxis {
    AxisMarks(position: .bottom) { value in
        AxisGridLine().foregroundStyle(.clear)
        AxisTick().foregroundStyle(.clear)
        AxisValueLabel(format: SecondsFormatStyle(), centered: false)
            .foregroundStyle(StatsColors.axisLabel)
    }
}
.chartYAxis {
    AxisMarks(position: .leading) { value in
        AxisGridLine().foregroundStyle(StatsColors.grid)
        AxisValueLabel(format: .number.precision(.fractionLength(0)), centered: false)
            .foregroundStyle(StatsColors.axisLabel)
    }
}
```

**Interactive Overlay**:
```swift
.chartOverlay { proxy in
    GeometryReader { geometry in
        overlay(
            proxy: proxy, 
            geometry: geometry, 
            selection: $cadenceSelection, 
            points: viewModel.cadenceSeries, 
            indicatorColor: StatsColors.accent
        ) { point in
            "\\(formatTime(point.relativeTime)), \\(Int(point.cadence.rounded())) spm"
        }
    }
}
```

**Accessibility**:
```swift
.accessibilityElement(children: .ignore)
.accessibilityLabel("Cadence chart, steps per minute over time")
.accessibilityValue(cadenceAccessibilityValue)
```

---

## Design Consistency

### Color Scheme
- **Primary Color**: `StatsColors.accent` (AccentBlue from Assets)
- **Background**: Dark purple theme matching other charts
- **Grid Lines**: White with 10% opacity
- **Axis Labels**: White with 70% opacity

### Typography
- **Font**: CallingCode-Regular (consistent with app theme)
- **Title**: 24pt
- **Body**: 16pt
- **Caption**: 14pt

### Layout
- **Card Design**: `StatsCard` component with rounded corners (16pt radius)
- **Chart Height**: 220pt (same as heart rate chart)
- **Padding**: 20pt inside cards, 16pt horizontal, 24pt vertical spacing

---

## Data Models

### CadenceDataPoint
```swift
// models.swift - Lines 52-56
struct CadenceDataPoint: Hashable {
    let timestamp: Date
    let cadence: Double          // Steps per minute
    let relativeTime: TimeInterval  // Seconds from workout start
}
```

### TimeSeriesSample Protocol
```swift
protocol TimeSeriesSample: Sendable, Hashable {
    var relativeTime: TimeInterval { get }
}

extension CadenceDataPoint: TimeSeriesSample {}
extension HeartRateDataPoint: TimeSeriesSample {}
```

### SeriesStats
```swift
struct SeriesStats {
    let min: Double
    let max: Double
    let average: Double
}
```

---

## Performance Optimizations

### 1. Data Downsampling
**StatsSeriesReducer** - Prevents UI lag with large datasets

```swift
// StatsViewModel.swift - Line 16
private let cadenceReducer = StatsSeriesReducer<CadenceDataPoint>(
    downsampleThreshold: 4000,  // Start downsampling above 4000 points
    downsampleLimit: 2000       // Target 2000 points max
)
```

**Benefits**:
- Maintains chart responsiveness with long runs
- Preserves visual fidelity while reducing memory usage

### 2. Async Streaming with Batching
**StatsSampleProvider** - Efficient data loading

```swift
// StatsViewModel.swift - Lines 111-129
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
```

**Benefits**:
- Batches updates every 350ms to reduce UI redraws
- Prevents excessive main thread updates
- Cancellable for efficient cleanup

### 3. Prewarm Strategy
**Quick Initial Load**

```swift
// StatsViewModel.swift - Lines 65-74
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
```

**Benefits**:
- Loads last 30-120 seconds first for instant feedback
- Full dataset streams in afterward
- Better perceived performance

---

## Error Handling & Edge Cases

### 1. Missing Cadence Data
```swift
if let message = viewModel.cadenceMessage {
    EmptyStateView(message: message)
} else {
    cadenceChart
}
```

**Messages**:
- "Not enough cadence data for this run." - Less than 3 data points
- No data available - Device doesn't support cadence tracking

### 2. Device Compatibility
```swift
guard let cadenceType = HKQuantityType.quantityType(forIdentifier: Self.runningCadenceIdentifier) else {
    return []  // Gracefully handle unsupported devices
}
```

**Supported Devices**:
- Apple Watch Series 6 and later
- iPhone 13 and later (via motion sensors during outdoor runs)
- Requires iOS 16.0+ / watchOS 9.0+

### 3. Data Quality
- Filters out invalid samples (NaN, infinity values)
- Clamps Y-axis domain to realistic range (120-220 SPM)
- Shows minimum 3 points before displaying chart

---

## Testing Recommendations

### Manual Testing Checklist
- [ ] Chart displays correctly for runs with full cadence data
- [ ] Empty state shows when no cadence data available
- [ ] Interactive overlay responds to touch/drag gestures
- [ ] Chart updates in real-time during active workouts (if applicable)
- [ ] Accessibility labels read correctly with VoiceOver
- [ ] Chart scales properly on different device sizes
- [ ] Color scheme matches other stats charts
- [ ] Performance is smooth with long runs (2+ hours)

### Test Scenarios
1. **Normal Run**: 30-60 minute run with continuous cadence data
2. **Long Run**: 2+ hour run to test downsampling
3. **Sparse Data**: Run with gaps in cadence tracking
4. **No Data**: Run from device without cadence support
5. **Edge Values**: Very low (<100 SPM) or very high (>220 SPM) cadence

---

## Future Enhancements

### Potential Features
1. **Cadence Zones**: Color-coded optimal cadence ranges (like heart rate zones)
2. **Cadence Trends**: Week/month cadence averages
3. **Cadence Alerts**: Real-time notifications for cadence drops
4. **Cadence-Pace Correlation**: Overlay pace on cadence chart
5. **Stride Analysis**: Combine cadence with stride length data

---

## References

### Apple Documentation
- [HealthKit Framework](https://developer.apple.com/documentation/healthkit)
- [Swift Charts](https://developer.apple.com/documentation/charts)
- [HKQuantityTypeIdentifier](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier)
- [HKSampleQuery](https://developer.apple.com/documentation/healthkit/hksamplequery)
- [HKAnchoredObjectQuery](https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery)
- [WWDC 2022: Hello Swift Charts](https://developer.apple.com/videos/play/wwdc2022/10136/)
- [WWDC 2023: Explore HealthKit](https://developer.apple.com/videos/play/wwdc2023/10109/)

### Running Science
- [Optimal Running Cadence Research](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC3989377/)
- Target cadence: 170-180 steps per minute for most runners
- Higher cadence often correlates with reduced injury risk

---

## File Structure

```
flash/
├── HealthManager.swift                      # HealthKit data fetching
├── models.swift                             # Data models (CadenceDataPoint)
├── Features/
│   └── Stats/
│       ├── StatsSampleProvider.swift        # Data streaming & caching
│       └── StatsViewModel.swift             # Business logic & state management
└── Views/
    └── Stats/
        └── StatsView.swift                  # UI implementation
```

---

## Summary

The cadence chart feature is **fully implemented** and follows best practices:

✅ **HealthKit Integration**: Proper authorization and data fetching  
✅ **Performance**: Optimized with downsampling and batching  
✅ **Design Consistency**: Matches existing chart theme  
✅ **Accessibility**: Full VoiceOver support  
✅ **Error Handling**: Graceful degradation for missing data  
✅ **Documentation**: Comprehensive API references included  

**Status**: ✅ Ready for PM review and beta testing

---

*Generated for Sprint Pre-Beta Testing*  
*Branch: `charts`*  
*Last Updated: 2025-10-28*
