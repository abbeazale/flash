//
//  HealthManager.swift
//  flash
//
//  Created by abbe on 2024-04-11.
//

import Foundation
import HealthKit
import CoreLocation

extension Calendar {
    static let gregorian = Calendar(identifier: .iso8601)
}

extension Date {
    func startOfYear(using calendar: Calendar = .gregorian) -> Date {
        calendar.dateComponents([.calendar, .yearForWeekOfYear], from: self).date!
    }

    func startOfMonth(using calendar: Calendar = .gregorian) -> Date {
        return Calendar.current.date(from: Calendar.current.dateComponents([.year, .month, .day], from: Calendar.current.startOfDay(for: self)))!
    }
}
//info from health kit
class HealthManager: ObservableObject {

    let healthStore = HKHealthStore()

    //@published makes it readable for the whole file
    /// Totals for the current Monday-to-Sunday week.
    @Published var thisWeek = WeekSummary.empty(weekStart: Date().startOfWeek())
    /// Monday of the week of the oldest run. Nil until HealthKit answers.
    @Published var firstRunWeekStart: Date?
    @Published var weeklyTimeRan = DateInterval()
    @Published var isLoading = true
    ///array of all runs
    @Published var allRuns = [RunningData]()

    // Add new property to track if we're loading more data
    @Published var isLoadingMore = false
    private let initialLoadLimit = 20

    @Published var hasMoreRuns = true
    private var isFetchingMore = false

    @Published private(set) var healthKitAuthorizationFinished = false
    @Published private(set) var healthKitAuthorizationSucceeded = false

    // Cache for weekly summary
    private let userDefaults = UserDefaults.standard
    private let weeklySummaryCacheKey = "weekSummaryCache.mondayFirst"

    //initalize the health manager getting the km and pace
    init() {
            // Load cached weekly summary immediately for instant UI
            loadCachedWeeklySummary()

            Task {
                let authorizationSucceeded = await requestAuthorization()
                await MainActor.run {
                    self.healthKitAuthorizationSucceeded = authorizationSucceeded
                    self.healthKitAuthorizationFinished = true
                }
                await loadHomeData()
            }
        }

    private func requestAuthorization() async -> Bool {
        let healthTypes: Set = [
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.runningSpeed),
            HKQuantityType.workoutType(),
            HKQuantityType(.heartRate),
            HKObjectType.activitySummaryType(),
            HKSampleType.workoutType()
        ]
        let readTypes: Set = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .runningPower)!,
            HKObjectType.quantityType(forIdentifier: .runningSpeed)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .runningStrideLength)!,
            HKObjectType.quantityType(forIdentifier: .runningVerticalOscillation)!,
            HKObjectType.quantityType(forIdentifier: .runningGroundContactTime)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKSeriesType.workoutRoute(),
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]

        do {
            try await healthStore.requestAuthorization(toShare: [], read: healthTypes)
            let success = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                healthStore.requestAuthorization(toShare: nil, read: readTypes) { success, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: success)
                    }
                }
            }
            print("Authorization successful: \(success)")
            return success
        } catch {
            print("Error requesting authorization: \(error.localizedDescription)")
            return false
        }
    }

    private func loadHomeData() async {
        await calculateWeeklySummary()
        let firstRunDate = await fetchFirstRunDate()
        await MainActor.run {
            self.firstRunWeekStart = firstRunDate?.startOfWeek()
        }

        await MainActor.run {
            self.isLoading = false
        }
    }

    private func processWorkout(_ workout: HKWorkout, maxHR: Double) async -> RunningData? {
        let stepCount = await getStepCount(for: workout)
        let totalTimeMinutes = workout.duration / 60
        let cadence = totalTimeMinutes > 0 ? stepCount / totalTimeMinutes : 0

        var elevationGain: Double = 0.0
        if let elevationQuantity = workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity {
            elevationGain = elevationQuantity.doubleValue(for: HKUnit.meter())
        }

        let power = await getAverageQuantity(for: workout, type: .runningPower)
        let pace = await getAverageQuantity(for: workout, type: .runningSpeed)
        let heartRate = await getAverageQuantity(for: workout, type: .heartRate)
        let strideLength = await getAverageQuantity(for: workout, type: .runningStrideLength)
        let verticalOscillation = await getAverageQuantity(for: workout, type: .runningVerticalOscillation)
        let groundContactTime = await getAverageQuantity(for: workout, type: .runningGroundContactTime)
        let activeCalories = await fetchActiveCalories(for: workout)
        let route = await fetchRoute(for: workout)

        // Fetch time-series heart rate and derive cadence from step samples.
        let heartRateData = await fetchHeartRateTimeSeries(for: workout)
        let cadenceData = await calculateCadenceFromSteps(for: workout)

        let heartRateZones = calculateHeartRateZones(
            heartRateData: heartRateData,
            averageHR: heartRate,
            maxHR: maxHR
        )

        let formattedDuration = formatDuration(workout.duration)
        let distance = workout.totalDistance?.doubleValue(for: .meter()) ?? 0.0
        let formattedPace = formatPace(duration: workout.duration, distance: distance)
        let formattedDurationD = formatDuration(workout.duration)
        let pacePerKM = calculatePacePerKM(route: route, totalDuration: workout.duration)

        return RunningData(
            date: workout.startDate,
            distance: distance,
            cadence: cadence,
            power: power,
            pace: pace,
            formattedPace: formattedPace,
            heartRate: heartRate,
            strideLength: strideLength,
            verticalOscillation: verticalOscillation,
            groundContactTime: groundContactTime,
            duration: workout.duration,
            formattedDuration: formattedDuration,
            elevation: elevationGain,
            activeCalories: activeCalories,
            route: route,
            formatDuration: formattedDurationD,
            pacePerKM: pacePerKM,
            heartRateData: heartRateData,
            cadenceData: cadenceData,
            heartRateZones: heartRateZones,
            healthKitUUID: workout.uuid
        )
    }

    private func makeRunSummary(from workout: HKWorkout) -> RunningData {
        let distance = workout.totalDistance?.doubleValue(for: .meter()) ?? 0.0
        let duration = workout.duration
        let formattedDuration = formatDuration(duration)
        let formattedPace = formatPace(duration: duration, distance: distance)
        let activeCalories = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0.0

        return RunningData(
            date: workout.startDate,
            distance: distance,
            cadence: 0,
            power: 0,
            pace: 0,
            formattedPace: formattedPace,
            heartRate: 0,
            strideLength: 0,
            verticalOscillation: 0,
            groundContactTime: 0,
            duration: duration,
            formattedDuration: formattedDuration,
            elevation: 0,
            activeCalories: activeCalories,
            route: [],
            formatDuration: formattedDuration,
            pacePerKM: [],
            heartRateData: [],
            cadenceData: [],
            heartRateZones: [],
            healthKitUUID: workout.uuid
        )
    }

    private func fetchRunningWorkoutSummaries(startDate: Date, limit: Int) async -> [RunningData] {
        let workoutType = HKSampleType.workoutType()
        let timePredicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let workoutPredicate = HKQuery.predicateForWorkouts(with: .running)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [timePredicate, workoutPredicate])
        let queryLimit = limit > 0 ? limit : HKObjectQueryNoLimit

        let workouts = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKWorkout], Error>) in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: queryLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples as? [HKWorkout] ?? [])
                }
            }
            healthStore.execute(query)
        }

        return workouts?.map(makeRunSummary) ?? []
    }

    private func fetchWorkout(uuid: UUID) async -> HKWorkout? {
        let workoutType = HKSampleType.workoutType()
        let predicate = HKQuery.predicateForObject(with: uuid)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: samples?.first as? HKWorkout)
            }
            healthStore.execute(query)
        }
    }

    func hydrateRunDetails(_ run: RunningData, maxHR: Double) async -> RunningData {
        guard run.route.isEmpty,
              run.heartRateData.isEmpty,
              run.cadenceData.isEmpty,
              run.pacePerKM.isEmpty,
              let healthKitUUID = run.healthKitUUID,
              let workout = await fetchWorkout(uuid: healthKitUUID) else {
            return run
        }

        return await processWorkout(workout, maxHR: maxHR) ?? run
    }

    // Method to load more runs (called when user scrolls to bottom)
    func loadMoreRuns() async {
        guard hasMoreRuns && !isFetchingMore else { return }
        await loadRunSummaryPage(limit: allRuns.count + initialLoadLimit)
    }

    private func unit(for type: HKQuantityTypeIdentifier) -> HKUnit {
        switch type {
        case .runningPower:
            return HKUnit.watt()
        case .runningSpeed:
            return HKUnit.meter().unitDivided(by: HKUnit.second()) // Use m/s for internal calculations
        case .heartRate:
            return HKUnit.count().unitDivided(by: HKUnit.minute())
        case .runningStrideLength:
            return HKUnit.meter()
        case .runningVerticalOscillation:
            return HKUnit.meterUnit(with: .centi)
        case .runningGroundContactTime:
            return HKUnit.secondUnit(with: .milli)
        default:
            return HKUnit.count()
        }
    }

    func calculatePacePerKM(route: [CLLocation], totalDuration _: TimeInterval) -> [SegmentPace] {
        calculatePaceSegments(route: route, segmentDistanceMeters: 1_000)
    }

    func calculatePaceSegments(
        route: [CLLocation],
        segmentDistanceMeters: Double
    ) -> [SegmentPace] {
        // RouteAnalyzer owns split boundaries so the map highlights the same points.
        RouteAnalyzer.splits(route: route, segmentDistanceMeters: segmentDistanceMeters).map {
            SegmentPace(
                kilometer: $0.number,
                pace: $0.paceMinutesPerKilometer,
                formattedPace: formatPace($0.paceMinutesPerKilometer)
            )
        }
    }

    // Fetch heart rate data points over time during the workout
    private func fetchHeartRateTimeSeries(for workout: HKWorkout) async -> [HeartRateDataPoint] {
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else {
                    continuation.resume(returning: [])
                    return
                }

                let startTime = workout.startDate
                let heartRatePoints = samples.map { sample -> HeartRateDataPoint in
                    let heartRate = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))
                    let relativeTime = sample.startDate.timeIntervalSince(startTime)
                    return HeartRateDataPoint(
                        timestamp: sample.startDate,
                        heartRate: heartRate,
                        relativeTime: relativeTime
                    )
                }

                continuation.resume(returning: heartRatePoints)
            }

            healthStore.execute(query)
        }
    }

    // Calculate cadence from step count because HealthKit does not expose a running-cadence quantity type in this SDK.
    private func calculateCadenceFromSteps(for workout: HKWorkout) async -> [CadenceDataPoint] {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: stepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error = error {
                    print("❌ Step count fetch error: \(error.localizedDescription)")
                    continuation.resume(returning: [])
                    return
                }

                guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else {
                    print("⚠️ No step count samples found")
                    continuation.resume(returning: [])
                    return
                }

                let startTime = workout.startDate
                var cadencePoints: [CadenceDataPoint] = []

                // Group step samples into larger time windows for more stable cadence
                // HealthKit step samples can be very short (1-2 seconds), causing spikes
                let timeWindow: TimeInterval = 30.0 // 30-second windows
                var windowStart = workout.startDate
                var stepsInWindow: Double = 0
                var durationInWindow: TimeInterval = 0

                func flushWindow() {
                    defer {
                        windowStart = windowStart.addingTimeInterval(timeWindow)
                        stepsInWindow = 0
                        durationInWindow = 0
                    }

                    guard stepsInWindow > 0 && durationInWindow >= 5 else { return }

                    let cadence = (stepsInWindow / durationInWindow) * 60.0

                    // Only include realistic cadence (100-220 SPM for running)
                    guard cadence >= 100 && cadence <= 220 else { return }

                    let relativeTime = windowStart.timeIntervalSince(startTime) + (timeWindow / 2)
                    cadencePoints.append(CadenceDataPoint(
                        timestamp: windowStart.addingTimeInterval(timeWindow / 2),
                        cadence: cadence,
                        relativeTime: relativeTime
                    ))
                }

                for sample in samples {
                    let steps = sample.quantity.doubleValue(for: HKUnit.count())
                    let sampleStart = max(sample.startDate, workout.startDate)
                    let sampleEnd = min(sample.endDate, workout.endDate)
                    let originalSampleDuration = sample.endDate.timeIntervalSince(sample.startDate)
                    let clippedSampleDuration = sampleEnd.timeIntervalSince(sampleStart)

                    guard steps > 0, originalSampleDuration > 0, clippedSampleDuration > 0 else {
                        continue
                    }

                    let stepsPerSecond = steps / originalSampleDuration
                    var cursor = sampleStart

                    while cursor < sampleEnd {
                        let windowEnd = windowStart.addingTimeInterval(timeWindow)

                        if !(cursor < windowEnd) { // Not `<=`/`>=`: those Date operators are weak-linked and crash on iOS 27.2 beta.
                            flushWindow()
                            continue
                        }

                        let overlapEnd = min(sampleEnd, windowEnd)
                        let overlapDuration = overlapEnd.timeIntervalSince(cursor)

                        guard overlapDuration > 0 else {
                            break
                        }

                        stepsInWindow += stepsPerSecond * overlapDuration
                        durationInWindow += overlapDuration
                        cursor = overlapEnd

                        if !(cursor < windowEnd) { // Not `<=`/`>=`: those Date operators are weak-linked and crash on iOS 27.2 beta.
                            flushWindow()
                        }
                    }
                }

                // Process the final window
                flushWindow()

                print("✅ Calculated \(cadencePoints.count) cadence points from step count")
                continuation.resume(returning: cadencePoints)
            }

            healthStore.execute(query)
        }
    }

    // Calculate heart rate zones based on time-series data
    // Standard zones: Zone 1 (50-60%), Zone 2 (60-70%), Zone 3 (70-80%), Zone 4 (80-90%), Zone 5 (90-100%)
    private func calculateHeartRateZones(
        heartRateData: [HeartRateDataPoint],
        averageHR: Double,
        maxHR: Double
    ) -> [HeartRateZone] {
        guard !heartRateData.isEmpty, maxHR.isFinite, maxHR > 0 else { return [] }

        // Define zones based on % of max HR
        let zones = [
            (name: "Zone 1", min: 0.50, max: 0.60, color: "#90EE90"),    // Light Green
            (name: "Zone 2", min: 0.60, max: 0.70, color: "#4CAF50"),    // Green
            (name: "Zone 3", min: 0.70, max: 0.80, color: "#FFA500"),    // Orange
            (name: "Zone 4", min: 0.80, max: 0.90, color: "#FF6347"),    // Red
            (name: "Zone 5", min: 0.90, max: 1.10, color: "#DC143C")     // Dark Red
        ]

        var zoneBreakdown: [HeartRateZone] = []
        let totalDataPoints = Double(heartRateData.count)

        for zone in zones {
            let minHR = maxHR * zone.min
            let maxZoneHR = maxHR * zone.max

            let pointsInZone = heartRateData.filter { dataPoint in
                dataPoint.heartRate >= minHR && dataPoint.heartRate < maxZoneHR
            }.count

            let percentage = (Double(pointsInZone) / totalDataPoints) * 100.0

            let hrZone = HeartRateZone(
                zone: zone.name,
                range: "\(Int(minHR))-\(Int(maxZoneHR)) bpm",
                percentage: percentage.rounded(toPlaces: 1),
                color: zone.color
            )

            zoneBreakdown.append(hrZone)
        }

        return zoneBreakdown
    }

    private func getAverageQuantity(for workout: HKWorkout, type: HKQuantityTypeIdentifier) async -> Double {
        let quantityType = HKQuantityType.quantityType(forIdentifier: type)!
        let predicate = HKQuery.predicateForObjects(from: workout)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: .discreteAverage) { _, result, _ in
                guard let result = result, let averageQuantity = result.averageQuantity() else {
                    continuation.resume(returning: 0.0)
                    return
                }
                var averageValue = averageQuantity.doubleValue(for: self.unit(for: type))

                // Convert speed from m/s to min/km
                if type == .runningSpeed {
                    averageValue = averageValue > 0 ? (1 / averageValue) * 16.6667 : 0 // 1 m/s = 16.6667 min/km
                }

                continuation.resume(returning: averageValue)
            }

            healthStore.execute(query)
        }
    }

    private func fetchActiveCalories(for workout: HKWorkout) async -> Double {
        let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: energyType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                let activeCalories = result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0.0
                continuation.resume(returning: activeCalories)
            }
            healthStore.execute(query)
        }
    }

    private func fetchRoute(for workout: HKWorkout) async -> ([CLLocation]) {
        let routeType = HKSeriesType.workoutRoute()
        let predicate = HKQuery.predicateForObjects(from: workout)

        return await withCheckedContinuation { continuation in
            let routeQuery = HKAnchoredObjectQuery(type: routeType, predicate: predicate, anchor: nil, limit: HKObjectQueryNoLimit) { query, samples, deletedObjects, newAnchor, error in
                if let error = error {
                    print("Error fetching route: \(error.localizedDescription)")
                    continuation.resume(returning: [])
                    return
                }

                if let routeSamples = samples as? [HKWorkoutRoute] {
                    let group = DispatchGroup()
                    // Create a thread-safe array using actor or serial queue
                    let serialQueue = DispatchQueue(label: "com.app.locations")
                    var threadSafeLocations: [CLLocation] = []

                    for routeSample in routeSamples {
                        group.enter()
                        let routeQuery = HKWorkoutRouteQuery(route: routeSample) { _, routeData, done, error in
                            if let error = error {
                                print("Error fetching route data: \(error.localizedDescription)")
                                group.leave()
                                return
                            }

                            if let routeData = routeData {
                                // Safely append to the array using serial queue
                                serialQueue.sync {
                                    threadSafeLocations.append(contentsOf: routeData)
                                }
                            }

                            if done {
                                group.leave()
                            }
                        }
                        self.healthStore.execute(routeQuery)
                    }

                    group.notify(queue: .main) {
                        // Route samples load concurrently; restore time order so splits and
                        // map highlights follow the run.
                        continuation.resume(
                            returning: threadSafeLocations.sorted { $0.timestamp < $1.timestamp }
                        )
                    }
                } else {
                    continuation.resume(returning: [])
                }
            }

            healthStore.execute(routeQuery)
        }
    }


    //put into min:sec
    //time interval is in secondsx
    private func formatDuration(_ duration: TimeInterval) -> String {
            let hours = Int(duration) / 3600

            let minutes = (Int(duration) % 3600) / 60
            let seconds = Int(duration) % 60
            return String(format: "%0d:%02d:%02d", hours, minutes, seconds)
        }

    ///takes time interval and distance
    ///returns the pace for the whole run
    func formatPace(duration: TimeInterval, distance: Double) -> String {
        guard distance > 0 else {
            return "N/A"
        }

        let pace = duration / distance // pace in seconds per meter
        let pacePerKm = pace * 1000 // convert to seconds per kilometer

        let minutes = Int(pacePerKm) / 60
        let seconds = Int(pacePerKm) % 60

        return String(format: "%02d:%02d/km", minutes, seconds)
    }

    ///formatted pace for each split
    func formatPace(_ pace: Double) -> String {
        guard pace.isFinite && !pace.isNaN && pace > 0 else {
            return "N/A"
        }

        let totalSeconds = pace * 60 // pace in seconds per km
        let minutes = Int(totalSeconds) / 60
        let seconds = Int(totalSeconds) % 60
        return String(format: "%0d:%02d", minutes, seconds)
    }

    private func getStepCount(for workout: HKWorkout) async -> Double {
        let quantityType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let predicate = HKQuery.predicateForObjects(from: workout)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let error = error {
                    print("Error fetching step count: \(error.localizedDescription)")
                    continuation.resume(returning: 0.0)
                    return
                }

                guard let result = result, let sumQuantity = result.sumQuantity() else {
                    continuation.resume(returning: 0.0)
                    return
                }

                let stepCount = sumQuantity.doubleValue(for: HKUnit.count())
                continuation.resume(returning: stepCount)
            }

            healthStore.execute(query)
        }
    }

    // Load cached weekly summary for instant UI
    private func loadCachedWeeklySummary() {
        guard let data = userDefaults.data(forKey: weeklySummaryCacheKey),
              let cached = try? JSONDecoder().decode(WeekSummary.self, from: data) else {
            return
        }

        // Use the cache only when it is for the current week
        if cached.weekStart == Date().startOfWeek() {
            self.thisWeek = cached
        }
    }

    // Save weekly summary to cache
    private func cacheWeeklySummary() {
        if let encoded = try? JSONEncoder().encode(thisWeek) {
            userDefaults.set(encoded, forKey: weeklySummaryCacheKey)
        }
    }

    // OPTIMIZED: Fetch only basic workout info without expensive details
    private func fetchBasicWorkouts(startDate: Date, endDate: Date) async -> [(date: Date, distance: Double, duration: TimeInterval)] {
        let workoutType = HKSampleType.workoutType()
        let timePredicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )
        let workoutPredicate = HKQuery.predicateForWorkouts(with: .running)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [timePredicate, workoutPredicate])

        let workouts = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKWorkout], Error>) in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let workouts = samples as? [HKWorkout], !workouts.isEmpty {
                    continuation.resume(returning: workouts)
                } else {
                    continuation.resume(returning: [])
                }
            }
            healthStore.execute(query)
        }

        guard let workouts = workouts else { return [] }

        // Only extract the basic info we need - no expensive queries!
        return workouts.map { workout in
            (
                date: workout.startDate,
                distance: workout.totalDistance?.doubleValue(for: .meter()) ?? 0.0,
                duration: workout.duration
            )
        }
    }

    /// Totals for the Monday-to-Sunday week that starts at `weekStart`.
    func weekSummary(for weekStart: Date) async -> WeekSummary {
        let empty = WeekSummary.empty(weekStart: weekStart)
        // Fetch only basic workout info (no routes, heart rate, etc.)
        let workouts = await fetchBasicWorkouts(startDate: weekStart, endDate: empty.weekEnd())
        return WeekSummary.make(
            weekStart: weekStart,
            runs: workouts.map {
                WeekRun(date: $0.date, distanceMeters: $0.distance, duration: $0.duration)
            }
        )
    }

    func calculateWeeklySummary() async {
        let summary = await weekSummary(for: Date().startOfWeek())

        await MainActor.run {
            self.thisWeek = summary
            // Cache the results for instant loading next time
            self.cacheWeeklySummary()
        }
    }

    /// Start date of the oldest running workout in HealthKit.
    func fetchFirstRunDate() async -> Date? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Date?, Never>) in
            let query = HKSampleQuery(
                sampleType: HKSampleType.workoutType(),
                predicate: HKQuery.predicateForWorkouts(with: .running),
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                continuation.resume(returning: samples?.first?.startDate)
            }
            healthStore.execute(query)
        }
    }
}

//chart data
extension HealthManager {

    ///fetches workouts with pagination - loads initial batch quickly
    func lottaRuns() async {
        await loadRunSummaryPage(limit: initialLoadLimit)
    }

    func loadRunSummaryPage(limit: Int) async {
        guard !isFetchingMore else { return }

        await MainActor.run {
            self.isFetchingMore = true
            self.isLoadingMore = !self.allRuns.isEmpty
        }

        let requestedLimit = max(initialLoadLimit, limit)
        let summaries = await fetchRunningWorkoutSummaries(startDate: .distantPast, limit: requestedLimit + 1)
        let visibleSummaries = Array(summaries.prefix(requestedLimit))

        await MainActor.run {
            self.allRuns = visibleSummaries
            self.hasMoreRuns = summaries.count > requestedLimit
            self.isFetchingMore = false
            self.isLoadingMore = false
        }
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
