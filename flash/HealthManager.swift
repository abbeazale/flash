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
    
    //initalize the health manager getting the km and pace
    init() {
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
        } catch {
            print("Error requesting authorization: \(error.localizedDescription)")
        }
    }
    
    private func loadAllData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchRunningWorkoutsFirestore() }
            group.addTask { await self.calculateWeeklySummary() }
        }
        
        DispatchQueue.main.async {
            self.isLoading = false
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
    
    func fetchRunningWorkouts(startDate: Date) async -> [RunningData] {
        let workoutType = HKSampleType.workoutType()
        let timePredicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let workoutPredicate = HKQuery.predicateForWorkouts(with: .running)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [timePredicate, workoutPredicate])

        let workouts = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKWorkout], Error>) in
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: 0, sortDescriptors: nil) { _, samples, error in
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
                    await self.firebaseManager.saveRunningData(runningData)
                }
            }
            return results.sorted { $0.date > $1.date }
        }

        await MainActor.run {
            self.allRuns = runningDataArray
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
            pacePerKM: pacePerKM
        )
    }
    
    //get the runs from the firestore database on launch
    func fetchRunningWorkoutsFirestore() async {
        let runningDataArray = await firebaseManager.fetchRunningData()
        DispatchQueue.main.async {
            self.allRuns = runningDataArray.sorted { $0.date > $1.date }
        }
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
        let newWorkouts = await fetchRunningWorkouts(startDate: Date().startOfYear())
        
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
        var locations: [CLLocation] = []
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
                    
                    for routeSample in routeSamples {
                        group.enter()
                        let routeQuery = HKWorkoutRouteQuery(route: routeSample) { _, routeData, done, error in
                            if let error = error {
                                print("Error fetching route data: \(error.localizedDescription)")
                                group.leave()
                                return
                            }
                            
                            if let routeData = routeData {
                                locations.append(contentsOf: routeData)
                            }
                            
                            if done {
                                group.leave()
                            }
                        }
                        self.healthStore.execute(routeQuery)
                    }
                    
                    group.notify(queue: .main) {
                        continuation.resume(returning: locations)
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
    
    func calculateWeeklySummary() async {
        let startDate = Date().startOfWeek()
        
        let runningDataArray = await fetchRunningWorkouts(startDate: startDate)
        
        // Filter workouts to include only those from the current week
        let calendar = Calendar.current
        let currentWeekWorkouts = runningDataArray.filter { calendar.isDate($0.date, equalTo: startDate, toGranularity: .weekOfYear) }
        
        // Calculate total distance, total duration, and average pace
        let totalDistance = currentWeekWorkouts.reduce(0.0) { $0 + $1.distance } / 1000 // Convert to kilometers
        let totalDuration = currentWeekWorkouts.reduce(0.0) { $0 + $1.duration } / 60 // Convert to minutes
        let averagePace = totalDuration > 0 ? totalDuration / totalDistance : 0.0 // min/km
        
        let runTimeFormatted = self.formatDuration(currentWeekWorkouts.reduce(0.0) { $0 + $1.duration })
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
        }
    }
}


//chart data
extension HealthManager {
    ///fetches all workouts at the start so it loads at the same time
    func lottaRuns() async {
        let runningData = await fetchRunningWorkouts(startDate: Date().startOfYear())
        await MainActor.run {
            self.allRuns = runningData
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
