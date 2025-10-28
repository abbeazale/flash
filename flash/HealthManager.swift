//
//  HealthManager.swift
//  flash
//
//  Created by abbe on 2024-04-11.
//

import Foundation
import HealthKit
import CoreLocation
import FirebaseFirestore

extension Calendar {
    static let gregorian = Calendar(identifier: .iso8601)
}

extension Date {
    func startOfWeek(using calendar: Calendar = .gregorian) -> Date {
        calendar.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: self).date!
    }
    
    func startOfYear(using calendar: Calendar = .gregorian) -> Date {
        calendar.dateComponents([.calendar, .yearForWeekOfYear], from: self).date!
    }
    
    func startOfMonth(using calendar: Calendar = .gregorian) -> Date {
        return Calendar.current.date(from: Calendar.current.dateComponents([.year, .month, .day], from: Calendar.current.startOfDay(for: self)))!
    }
    
    func endOfWeek(using calendar: Calendar = .gregorian) -> Date {
            let startOfWeek = self.startOfWeek(using: calendar)
            return calendar.date(byAdding: .day, value: 6, to: startOfWeek)!
        }
}
//info from health kit
class HealthManager: ObservableObject {
    
    let healthStore = HKHealthStore()
    let firebaseManager = FirebaseManager()
    
    //@published makes it readable for the whole file
    //total km for the week
    @Published var weeklyRunDistance: Double = 0
    @Published var weeklyRunTime: Double = 0
    @Published var weeklyRunPace: Double = 0
    @Published var formattedRunTime: String = ""
    @Published var formattedRunPace: String = ""
    @Published var weeklyTimeRan = DateInterval()
    @Published var isLoading = true
    ///array of all runs
    @Published var allRuns = [RunningData]()
    
    //data points for runs
    @Published var weeklyRunSummery = [WeeklyRunData]()
    
    //timer for syncing new runs
    private var syncTimer: Timer?
    
    // Add new property to track if we're loading more data
    @Published var isLoadingMore = false
    private let initialLoadLimit = 20
    
    // Pagination state for Firebase
    private var lastFirebaseDocument: DocumentSnapshot?
    @Published var hasMoreRuns = true
    private var isFetchingMore = false
    
    // Cache for weekly summary
    private var cachedWeeklySummaryDate: Date?
    private let userDefaults = UserDefaults.standard
    private let weeklySummaryCacheKey = "weeklySummaryCache"
    
    //initalize the health manager getting the km and pace
    init() {
            // Load cached weekly summary immediately for instant UI
            loadCachedWeeklySummary()
            
            Task {
                await requestAuthorization()
                await loadAllData()
            }
        }
    
    private func requestAuthorization() async {
        let healthTypes: Set = [
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.runningSpeed),
            HKQuantityType.workoutType(),
            HKQuantityType(.heartRate),
            HKObjectType.activitySummaryType(),
            HKSampleType.workoutType()
        ]
        var readTypes: Set = [
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

        // Add running cadence if available (iOS 16.0+, watchOS 9.0+)
        // Try multiple possible identifier strings
        let possibleCadenceIdentifiers = [
            "HKQuantityTypeIdentifierRunningCadence",
            "RunningCadence",
            "HKQuantityTypeIdentifierAppleRunningCadence"
        ]
        
        var cadenceTypeAdded = false
        for identifierString in possibleCadenceIdentifiers {
            let cadenceIdentifier = HKQuantityTypeIdentifier(rawValue: identifierString)
            if let runningCadenceType = HKObjectType.quantityType(forIdentifier: cadenceIdentifier) {
                readTypes.insert(runningCadenceType)
                print("✅ Running cadence type added using identifier: \(identifierString)")
                cadenceTypeAdded = true
                break
            }
        }
        
        if !cadenceTypeAdded {
            print("⚠️ Running cadence type not available. Tried identifiers: \(possibleCadenceIdentifiers)")
            print("   Device: iOS \(UIDevice.current.systemVersion)")
            print("   Note: Will calculate cadence from step count instead")
        }
        
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
        } catch {
            print("Error requesting authorization: \(error.localizedDescription)")
        }
    }
    
    private func loadAllData() async {
        // Calculate weekly summary FIRST (it's faster now)
        await calculateWeeklySummary()
        
        // Then load runs data
        let initialData = await fetchRunningWorkouts(
            startDate: .distantPast,
            limit: initialLoadLimit
        )
        
        await MainActor.run {
            self.allRuns = initialData.sorted { $0.date > $1.date }
            self.isLoading = false // Stop loading indicator after initial load
        }
        
        // Load remaining data in background
        Task {
            await self.loadRemainingData()
        }
    }
    
    private func loadRemainingData() async {
        await MainActor.run {
            self.isLoadingMore = true
        }
        
        let allData = await fetchRunningWorkouts(
            startDate: .distantPast,
            limit: 0 // 0 means no limit
        )
        
        await MainActor.run {
            self.allRuns = allData.sorted { $0.date > $1.date }
            self.isLoadingMore = false
        }
        
        // Save to Firebase in background
        Task {
            for runData in allData {
                await self.firebaseManager.saveRunningData(runData)
            }
        }
    }
    
    //data is fetched asynchronously
    //gets the data ran for the week
    func fetchWeeklyInfo(startDate: Date, completion: @escaping ([WeeklyRunData]) -> Void ) {
        let distance = HKQuantityType(.distanceWalkingRunning)
        //puts the two querys of within the last month and running
        let interval = DateComponents(day: 1)
        
        let query = HKStatisticsCollectionQuery(quantityType: distance, quantitySamplePredicate: nil, anchorDate: Date().startOfYear(), intervalComponents: interval)
        
        query.initialResultsHandler = {query, result, error in
            guard let result = result else {
                completion([])
                return
            }
            
            var totalD = [WeeklyRunData]()
            
            result.enumerateStatistics(from: startDate, to: Date()) { statistics, stop in
                totalD.append(WeeklyRunData(date: statistics.startDate, kmRan:
                                                statistics.sumQuantity()?.doubleValue(for: .meterUnit(with: .kilo)) ?? 0.00))
            }
            completion(totalD)
           
            //total distance
            let td = totalD.map {$0.kmRan}
            
            let sum = td.reduce(0, { x, y in
                x + y
            })
            //print(sum)
            DispatchQueue.main.async {
                self.weeklyRunDistance = sum
            
            }
            
        }
        
        healthStore.execute(query)
    }
    
    func fetchRunningWorkouts(startDate: Date, limit: Int = 0) async -> [RunningData] {
        let workoutType = HKSampleType.workoutType()
        let timePredicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let workoutPredicate = HKQuery.predicateForWorkouts(with: .running)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [timePredicate, workoutPredicate])

        let workouts = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKWorkout], Error>) in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: limit, // Use the limit parameter
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

        guard let workouts = workouts, !workouts.isEmpty else {
            print("No workouts found")
            return []
        }

        let runningDataArray = await withTaskGroup(of: RunningData?.self) { group in
            for workout in workouts {
                group.addTask {
                    await self.processWorkout(workout)
                }
            }

            var results: [RunningData] = []
            for await result in group {
                if let runningData = result {
                    results.append(runningData)
                }
            }
            return results.sorted { $0.date > $1.date }
        }

        return runningDataArray
    }

    private func processWorkout(_ workout: HKWorkout) async -> RunningData? {
        let stepCount = await getStepCount(for: workout)
        let totalTimeMinutes = workout.duration / 60
        let cadence = stepCount / totalTimeMinutes

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
        
        // Fetch time-series heart rate and cadence data
        let heartRateData = await fetchHeartRateTimeSeries(for: workout)
        var cadenceData = await fetchCadenceTimeSeries(for: workout)
        
        // If no cadence sensor data available, calculate from steps as fallback
        if cadenceData.isEmpty {
            print("ℹ️ No cadence sensor data, calculating from step count")
            cadenceData = await calculateCadenceFromSteps(for: workout)
        }
        
        let heartRateZones = calculateHeartRateZones(heartRateData: heartRateData, averageHR: heartRate)

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
            heartRateZones: heartRateZones
        )
    }
    
    //get the runs from the firestore database on launch with pagination
    func fetchRunningWorkoutsFirestore(loadMore: Bool = false) async {
        // Prevent multiple simultaneous fetches
        guard !isFetchingMore else { return }
        
        await MainActor.run {
            self.isFetchingMore = true
            if loadMore {
                self.isLoadingMore = true
            } else {
                self.isLoading = true
            }
        }
        
        let result = await firebaseManager.fetchRunningData(
            limit: 20,
            startAfter: loadMore ? lastFirebaseDocument : nil
        )
        
        await MainActor.run {
            if loadMore {
                // Append new runs to existing ones
                self.allRuns.append(contentsOf: result.runs)
            } else {
                // Replace with new runs
                self.allRuns = result.runs
            }
            
            self.lastFirebaseDocument = result.lastDocument
            self.hasMoreRuns = result.hasMore
            self.isFetchingMore = false
            self.isLoadingMore = false
            self.isLoading = false
        }
    }
    
    // Method to load more runs (called when user scrolls to bottom)
    func loadMoreRuns() async {
        guard hasMoreRuns && !isFetchingMore else { return }
        await fetchRunningWorkoutsFirestore(loadMore: true)
    }

    func startPeriodSync() {
        // Calls the timer function every hour
        syncTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.fetchAndSyncWorkouts()
            }
        }
    }
    
    //method to get new workouts and save it to the database
    private func fetchAndSyncWorkouts() async {
        let newWorkouts = await fetchRunningWorkouts(startDate: .distantPast)
        
        // Filter workouts that are already saved
        let existingWorkoutDates = Set(allRuns.map { $0.date })
        let newWorkoutsToSave = newWorkouts.filter { !existingWorkoutDates.contains($0.date) }
        
        // Save new workouts to Firebase
        for workout in newWorkoutsToSave {
            await firebaseManager.saveRunningData(workout)
        }
        
        // Refresh local data with new data
        await fetchRunningWorkoutsFirestore()
    }
    
    ///method to stop the periodic syncing
    func stopSync(){
        syncTimer?.invalidate()
        syncTimer = nil
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
    
    func calculatePacePerKM(route: [CLLocation], totalDuration: TimeInterval) -> [SegmentPace] {
            guard !route.isEmpty else { return [] }
            
            var segmentPaces: [SegmentPace] = []
            var currentKilometer = 1
            var segmentDistance: Double = 0.0
            var segmentTime: TimeInterval = 0.0
            var lastLocation = route.first!
            
            for location in route.dropFirst() {
                let distance = location.distance(from: lastLocation)
                segmentDistance += distance
                segmentTime += location.timestamp.timeIntervalSince(lastLocation.timestamp)
                
                if segmentDistance >= 1000 {
                    let pace = segmentTime / 60 / (segmentDistance / 1000)
                    let formattedPace = formatPace(pace)
                    let segmentPace = SegmentPace(kilometer: currentKilometer, pace: pace, formattedPace: formattedPace)
                    segmentPaces.append(segmentPace)
                    currentKilometer += 1
                    segmentDistance = 0.0
                    segmentTime = 0.0
                }
                
                lastLocation = location
            }
            
            if segmentDistance > 0 {
                let pace = segmentTime / 60.0 / (segmentDistance / 1000)
                let formattedPace = formatPace(pace)
                let segmentPace = SegmentPace(kilometer: currentKilometer, pace: pace, formattedPace: formattedPace)
                segmentPaces.append(segmentPace)
            }
            
            return segmentPaces
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

    private func fetchCadenceTimeSeries(for workout: HKWorkout) async -> [CadenceDataPoint] {
        // Running cadence requires iOS 16.0+
        guard #available(iOS 16.0, *) else {
            print("⚠️ Cadence: Requires iOS 16.0 or later (current iOS version too old)")
            return []
        }
        
        // Try to get the running cadence type using the raw value identifier
        let cadenceIdentifier = HKQuantityTypeIdentifier(rawValue: "HKQuantityTypeIdentifierRunningCadence")
        guard let cadenceType = HKQuantityType.quantityType(forIdentifier: cadenceIdentifier) else {
            print("⚠️ Cadence: Running cadence type not available on this device")
            return []
        }

        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: cadenceType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error = error {
                    print("❌ Cadence fetch error: \(error.localizedDescription)")
                    continuation.resume(returning: [])
                    return
                }
                
                guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else {
                    print("⚠️ Cadence: No samples found for workout on \(workout.startDate)")
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

                print("✅ Cadence: Fetched \(cadencePoints.count) samples for workout")
                continuation.resume(returning: cadencePoints)
            }

            healthStore.execute(query)
        }
    }
    
    // Fallback: Calculate cadence from step count when sensor data unavailable
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
                
                for sample in samples {
                    let steps = sample.quantity.doubleValue(for: HKUnit.count())
                    let sampleDuration = sample.endDate.timeIntervalSince(sample.startDate)
                    
                    // If this sample goes beyond the current window, finalize the window
                    while sample.endDate > windowStart.addingTimeInterval(timeWindow) {
                        if stepsInWindow > 0 && durationInWindow >= 5 { // Need at least 5 seconds of data
                            let cadence = (stepsInWindow / durationInWindow) * 60.0
                            
                            // Only include realistic cadence (100-220 SPM for running)
                            if cadence >= 100 && cadence <= 220 {
                                let relativeTime = windowStart.timeIntervalSince(startTime) + (timeWindow / 2)
                                cadencePoints.append(CadenceDataPoint(
                                    timestamp: windowStart.addingTimeInterval(timeWindow / 2),
                                    cadence: cadence,
                                    relativeTime: relativeTime
                                ))
                            }
                        }
                        
                        // Move to next window
                        windowStart = windowStart.addingTimeInterval(timeWindow)
                        stepsInWindow = 0
                        durationInWindow = 0
                    }
                    
                    // Add this sample to the current window
                    if sample.startDate >= windowStart {
                        stepsInWindow += steps
                        durationInWindow += sampleDuration
                    }
                }
                
                // Process the final window
                if stepsInWindow > 0 && durationInWindow >= 5 {
                    let cadence = (stepsInWindow / durationInWindow) * 60.0
                    if cadence >= 100 && cadence <= 220 {
                        let relativeTime = windowStart.timeIntervalSince(startTime) + (timeWindow / 2)
                        cadencePoints.append(CadenceDataPoint(
                            timestamp: windowStart.addingTimeInterval(timeWindow / 2),
                            cadence: cadence,
                            relativeTime: relativeTime
                        ))
                    }
                }
                
                print("✅ Calculated \(cadencePoints.count) cadence points from step count")
                continuation.resume(returning: cadencePoints)
            }
            
            healthStore.execute(query)
        }
    }
    
    // Calculate heart rate zones based on time-series data
    // Standard zones: Zone 1 (50-60%), Zone 2 (60-70%), Zone 3 (70-80%), Zone 4 (80-90%), Zone 5 (90-100%)
    private func calculateHeartRateZones(heartRateData: [HeartRateDataPoint], averageHR: Double) -> [HeartRateZone] {
        guard !heartRateData.isEmpty else { return [] }
        
        // Estimate max heart rate (220 - age), or use highest recorded HR * 1.05 as a fallback
        let maxHR = heartRateData.map { $0.heartRate }.max() ?? averageHR
        let estimatedMaxHR = max(maxHR * 1.05, 180.0) // Use 180 as minimum max HR
        
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
            let minHR = estimatedMaxHR * zone.min
            let maxHR = estimatedMaxHR * zone.max
            
            let pointsInZone = heartRateData.filter { dataPoint in
                dataPoint.heartRate >= minHR && dataPoint.heartRate < maxHR
            }.count
            
            let percentage = (Double(pointsInZone) / totalDataPoints) * 100.0
            
            let hrZone = HeartRateZone(
                zone: zone.name,
                range: "\(Int(minHR))-\(Int(maxHR)) bpm",
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
                    averageValue = (1 / averageValue) * 16.6667 // 1 m/s = 16.6667 min/km
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
                        continuation.resume(returning: threadSafeLocations)
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
            return "u didnt even run"
        }

        let pace = duration / distance // pace in seconds per meter
        let pacePerKm = pace * 1000 // convert to seconds per kilometer

        let minutes = Int(pacePerKm) / 60
        let seconds = Int(pacePerKm) % 60

        return String(format: "%02d:%02d/km", minutes, seconds)
    }
    
    ///formatted pace for each split
    func formatPace(_ pace: Double) -> String {
        guard pace.isFinite && !pace.isNaN else {
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
              let cached = try? JSONDecoder().decode(WeeklySummaryCache.self, from: data) else {
            return
        }
        
        // Check if cache is from current week
        let calendar = Calendar.current
        let currentWeekStart = Date().startOfWeek()
        
        if calendar.isDate(cached.weekStartDate, equalTo: currentWeekStart, toGranularity: .weekOfYear) {
            // Cache is valid, use it immediately
            self.weeklyRunDistance = cached.totalDistance
            self.weeklyRunTime = cached.totalDuration
            self.weeklyRunPace = cached.averagePace
            self.formattedRunTime = cached.formattedTime
            self.formattedRunPace = cached.formattedPace
            self.weeklyRunSummery = cached.weeklyData
            self.cachedWeeklySummaryDate = cached.weekStartDate
        }
    }
    
    // Save weekly summary to cache
    private func cacheWeeklySummary() {
        let cache = WeeklySummaryCache(
            weekStartDate: Date().startOfWeek(),
            totalDistance: weeklyRunDistance,
            totalDuration: weeklyRunTime,
            averagePace: weeklyRunPace,
            formattedTime: formattedRunTime,
            formattedPace: formattedRunPace,
            weeklyData: weeklyRunSummery
        )
        
        if let encoded = try? JSONEncoder().encode(cache) {
            userDefaults.set(encoded, forKey: weeklySummaryCacheKey)
        }
    }
    
    // OPTIMIZED: Fetch only basic workout info without expensive details
    private func fetchBasicWorkouts(startDate: Date) async -> [(date: Date, distance: Double, duration: TimeInterval)] {
        let workoutType = HKSampleType.workoutType()
        let timePredicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
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
    
    func calculateWeeklySummary() async {
        let startDate = Date().startOfWeek()
        
        // OPTIMIZED: Fetch only basic workout info (no routes, heart rate, etc.)
        let basicWorkouts = await fetchBasicWorkouts(startDate: startDate)
        
        // Filter workouts to include only those from the current week
        let calendar = Calendar.current
        let currentWeekWorkouts = basicWorkouts.filter { calendar.isDate($0.date, equalTo: startDate, toGranularity: .weekOfYear) }
        
        // Calculate total distance, total duration, and average pace
        let totalDistance = currentWeekWorkouts.reduce(0.0) { $0 + $1.distance } / 1000 // Convert to kilometers
        let totalDuration = currentWeekWorkouts.reduce(0.0) { $0 + $1.duration } / 60 // Convert to minutes
        let averagePace = totalDuration > 0 ? totalDuration / totalDistance : 0.0 // min/km
        
        let totalDurationSeconds = currentWeekWorkouts.reduce(0.0) { $0 + $1.duration }
        let runTimeFormatted = self.formatDuration(totalDurationSeconds)
        let runPaceFormatted = self.formatPace(averagePace)
        
        // Create WeeklyRunData for each day in the current week
        let weeklyRunData = currentWeekWorkouts.map { workout in
            WeeklyRunData(date: workout.date, kmRan: (workout.distance / 1000).rounded(toPlaces: 2))
        }
        
        // Update @Published properties
        await MainActor.run {
            self.weeklyRunDistance = totalDistance.rounded(toPlaces: 2)
            self.weeklyRunTime = totalDuration.rounded(toPlaces: 2)
            self.weeklyRunPace = averagePace.rounded(toPlaces: 2)
            self.weeklyRunSummery = weeklyRunData
            self.formattedRunTime = runTimeFormatted
            self.formattedRunPace = runPaceFormatted
            
            // Cache the results for instant loading next time
            self.cacheWeeklySummary()
        }
    }
}

// Cache structure for weekly summary
private struct WeeklySummaryCache: Codable {
    let weekStartDate: Date
    let totalDistance: Double
    let totalDuration: Double
    let averagePace: Double
    let formattedTime: String
    let formattedPace: String
    let weeklyData: [WeeklyRunData]
}

// Make WeeklyRunData Codable for caching
extension WeeklyRunData: Codable {
    enum CodingKeys: String, CodingKey {
        case date, kmRan
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let date = try container.decode(Date.self, forKey: .date)
        let kmRan = try container.decode(Double.self, forKey: .kmRan)
        self.init(date: date, kmRan: kmRan)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(kmRan, forKey: .kmRan)
    }
}


//chart data
extension HealthManager {
    
    ///fetches workouts with pagination - loads initial batch quickly
    func lottaRuns() async {
        // First, try to load from Firebase (faster)
        await fetchRunningWorkoutsFirestore(loadMore: false)
        
        // If no data from Firebase, fall back to HealthKit
        if allRuns.isEmpty {
            let runningData = await fetchRunningWorkouts(startDate: .distantPast, limit: initialLoadLimit)
            await MainActor.run {
                self.allRuns = runningData
            }
        }
    }
}

extension Date {
    func startOfWeekM() -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return calendar.date(from: components)!.addingTimeInterval(60*60*24) // Adjust to start from Monday
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
