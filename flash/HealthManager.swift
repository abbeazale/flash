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
    //tptal km for the week
    @Published var weeklyRunDistance: Double = 0
    @Published var weeklyRunTime: Double = 0
    @Published var weeklyRunPace: Double = 0
    @Published var formattedRunTime: String = ""
    @Published var formattedRunPace: String = ""
    
    @Published var weeklyTimeRan = DateInterval()
    
    @Published var allRuns = [RunningData]()
    
    //data points for runs
    @Published var weeklyRunSummery = [WeeklyRunData]()
    
    //timer for syncing new runs
    private var syncTimer: Timer?
    
    //initalize the health manager getting the km and pace
    init(){
        //gets total km the usuer has ran or walked
        let totalKm = HKQuantityType(.distanceWalkingRunning)
        let workouts = HKQuantityType.workoutType()
        let heartRate = HKQuantityType(.heartRate)
        let type = HKObjectType.activitySummaryType()
        let runs = HKSampleType.workoutType()
        
        //pace
        let pace = HKQuantityType(.runningSpeed)
        
        //what its asking for permission from user
        let healthTypes: Set = [totalKm, pace, workouts, heartRate, type, runs]
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
                HKObjectType.quantityType(forIdentifier: .heartRate)!,
                HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
                HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
                
            ]
        
        //getting the health data
        Task {
            do {
                //reading the health types
                try await healthStore.requestAuthorization(toShare: [], read: healthTypes)
                await healthStore.requestAuthorization(toShare: nil, read: readTypes) { success, error in
                        if let error = error {
                            print("Error requesting authorization: \(error.localizedDescription)")
                        } else {
                            print("Authorization successful: \(success)")
                        }
                    }
                //oneWeekData()
                lottaRuns()
                calculateWeeklySummary()
                    
              
                
                //print(totalKm)
            } catch {
                print("error getting health data ")
            }
        }
    }
   
    //data is fetched asynchronously
    //gets an array of dates
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
            //print(totalD.map {$0.kmRan})
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
    
    func fetchWorkouts() {
        let timePredicate = HKQuery.predicateForSamples(withStart: Date().startOfMonth(), end: Date())
        let workout = HKSampleType.workoutType()
        //searches only for this running type
        let workoutPredicate = HKQuery.predicateForWorkouts(with: .running)
        //puts the two querys of within the last month and running
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [timePredicate, workoutPredicate])
        
        //returns an array of HK samples (running workouts)
        let query = HKSampleQuery(sampleType: workout, predicate: predicate, limit: 10, sortDescriptors: nil){_, sample, error in
            
            guard let workouts = sample as? [HKWorkout], error == nil else {
                print("error getting the info for the week ")
                return
            }
    
        }
        
        healthStore.execute(query)
    }
    
    func fetchRunningWorkouts(startDate: Date, completion: @escaping ([RunningData]) -> Void) {
        let workoutType = HKSampleType.workoutType()
        let timePredicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
        let workoutPredicate = HKQuery.predicateForWorkouts(with: .running)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [timePredicate, workoutPredicate])

        let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: 0, sortDescriptors: nil) { _, samples, error in
            if let error = error {
                print("Error fetching workouts: \(error.localizedDescription)")
                completion([])
                return
            }

            guard let workouts = samples as? [HKWorkout], !workouts.isEmpty else {
                print("No workouts found")
                completion([])
                return
            }

            var runningDataArray: [RunningData] = []
            let group = DispatchGroup()

            for workout in workouts {
                group.enter()
                self.getStepCount(for: workout) { stepCount in
                    let totalTimeMinutes = workout.duration / 60
                    let cadence = stepCount / totalTimeMinutes

                    var elevationGain: Double = 0.0
                    if let elevationQuantity = workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity {
                        elevationGain = elevationQuantity.doubleValue(for: HKUnit.meter())
                    }

                    self.getAverageQuantity(for: workout, type: .runningPower) { power in
                        self.getAverageQuantity(for: workout, type: .runningSpeed) { pace in
                            self.getAverageQuantity(for: workout, type: .heartRate) { heartRate in
                                self.getAverageQuantity(for: workout, type: .runningStrideLength) { strideLength in
                                    self.getAverageQuantity(for: workout, type: .runningVerticalOscillation) { verticalOscillation in
                                        self.getAverageQuantity(for: workout, type: .runningGroundContactTime) { groundContactTime in
                                            
                                            // Fetch active calories
                                            self.fetchActiveCalories(for: workout) { activeCalories in
                                                
                                                // Fetch route data
                                                self.fetchRoute(for: workout) { route in
                                                    
                                                    let formattedDuration = self.formatDuration(workout.duration)
                                                    let distance = workout.totalDistance?.doubleValue(for: .meter()) ?? 0.0
                                                    let formattedPace = self.formatPace(duration: workout.duration, distance: distance)
                                                    let formattedDurationD = self.formatDuration(workout.duration)
                                                   let runningData = RunningData(
                                                       date: workout.startDate,
                                                       distance: workout.totalDistance?.doubleValue(for: .meter()) ?? 0.0,
                                                       cadence: cadence,
                                                       power: power,
                                                       pace: workout.duration / distance, // This is the raw pace value in minutes per kilometer
                                                       formattedPace: formattedPace, // This is the formatted pace value
                                                       heartRate: heartRate,
                                                       strideLength: strideLength,
                                                       verticalOscillation: verticalOscillation,
                                                       groundContactTime: groundContactTime,
                                                       duration: workout.duration,
                                                       formattedDuration: formattedDuration,
                                                       elevation: elevationGain,
                                                       activeCalories: activeCalories,
                                                       route: route,
                                                       formatDuration: formattedDurationD
                                                    )
                                                    runningDataArray.append(runningData)
                                                    
                                                    //saves the info to firebaswe
                                                    self.firebaseManager.saveRunningData(runningData)
                                                    group.leave()
                                                }
                                            }
                                        }
                                    }
                                    
                                }
                            }
                        }
                    }
                }
            }

            group.notify(queue: .main) {
                runningDataArray.sort { $0.date > $1.date }
                //print(runningDataArray.map { $0.date })
                self.allRuns = runningDataArray
                completion(runningDataArray)
            }
        }

        healthStore.execute(query)
    }
    
    //get the runs from the firestore database on launch
    func fetchRunningWorkoutsFirestore(){
        
        firebaseManager.fetchRunningData{[weak self] runningDataArray in
            DispatchQueue.main.async {
                self?.allRuns = runningDataArray.sorted{$0.date>$1.date}
            }
        }
    }

    func startPeriodSync(){
        //calls the timer function every hour
        syncTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true){ [weak self] _ in
            self?.fetchAndSyncWorkouts()
        }
    }
    
    //method to get new workouts and save it to the database
    private func fetchAndSyncWorkouts(){
        fetchRunningWorkouts(startDate: Date().startOfYear()){[weak self] newWorkouts in
            guard let self = self else {return}
            
            //filter workouts that are already saved
            let existingWorkoutDates = Set(self.allRuns.map {$0.date})
            let newWorkoutsToSave = newWorkouts.filter{!existingWorkoutDates.contains($0.date)}
            
            //save new workouts to firebase
            for workout in newWorkoutsToSave {
                self.firebaseManager.saveRunningData(workout)
                
            }
            
            //refresh local data w new data
            self.fetchRunningWorkoutsFirestore()
            
        }
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
    
    private func getAverageQuantity(for workout: HKWorkout, type: HKQuantityTypeIdentifier, completion: @escaping (Double) -> Void) {
        let quantityType = HKQuantityType.quantityType(forIdentifier: type)!
        let predicate = HKQuery.predicateForObjects(from: workout)

        let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: .discreteAverage) { _, result, _ in
            guard let result = result, let averageQuantity = result.averageQuantity() else {
                completion(0.0)
                return
            }
            var averageValue = averageQuantity.doubleValue(for: self.unit(for: type))
            
            // Convert speed from m/s to min/km
            if type == .runningSpeed {
                averageValue = (1 / averageValue) * 16.6667 // 1 m/s = 16.6667 min/km
            }
            
            completion(averageValue)
        }

        healthStore.execute(query)
    }
    
    private func fetchActiveCalories(for workout: HKWorkout, completion: @escaping (Double) -> Void) {
        let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate)
        
        let query = HKStatisticsQuery(quantityType: energyType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
            let activeCalories = result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0.0
            completion(activeCalories)
        }
        healthStore.execute(query)
    }
    
    private func fetchRoute(for workout: HKWorkout, completion: @escaping ([CLLocation]) -> Void) {
        var locations: [CLLocation] = []
        let routeType = HKSeriesType.workoutRoute()
        let predicate = HKQuery.predicateForObjects(from: workout)
        
        let routeQuery = HKAnchoredObjectQuery(type: routeType, predicate: predicate, anchor: nil, limit: HKObjectQueryNoLimit) { query, samples, deletedObjects, newAnchor, error in
            if let error = error {
                print("Error fetching route: \(error.localizedDescription)")
                completion([])
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
                    completion(locations)
                }
            } else {
                completion([])
            }
        }
        
        healthStore.execute(routeQuery)
    }
    
    
    //put into min:sec
    //time interval is in secondsx
    private func formatDuration(_ duration: TimeInterval) -> String {
            let hours = Int(duration) / 3600
            print(duration)
            print(hours)
            let minutes = (Int(duration) % 3600) / 60
            let seconds = Int(duration) % 60
            return String(format: "%0d:%02d:%02d", hours, minutes, seconds)
        }
    
    ///takes time interval and distance
    private func formatPace(duration: TimeInterval, distance: Double) -> String {
        guard distance > 0 else {
            return "N/A"
        }

        let pace = duration / distance // pace in seconds per meter
        let pacePerKm = pace * 1000 // convert to seconds per kilometer

        let minutes = Int(pacePerKm) / 60
        let seconds = Int(pacePerKm) % 60

        return String(format: "%02d:%02d / km", minutes, seconds)
    }
    
    ///if pace is already calculated
    private func formatPace(_ pace: Double) -> String {
        guard pace.isFinite && !pace.isNaN else {
            return "N/A"
        }

        let totalSeconds = pace * 60 // pace in seconds per km
        let minutes = Int(totalSeconds) / 60
        let seconds = Int(totalSeconds) % 60
        return String(format: "%0d:%02d / km", minutes, seconds)
    }
    
    private func getStepCount(for workout: HKWorkout, completion: @escaping (Double) -> Void) {
        // Define the quantity type for step count and filter for step count from the workouts
        let quantityType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let predicate = HKQuery.predicateForObjects(from: workout)
        
        // Create a statistics query to sum the step count samples
        let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
            // Check if the result is valid and contains a sum quantity
            guard let result = result, let sumQuantity = result.sumQuantity() else {
                // If no data is found, return 0.0
                completion(0.0)
                return
            }
            let stepCount = sumQuantity.doubleValue(for: HKUnit.count())
            
            // Return the step count value through the completion handler
            completion(stepCount)
        }
        
        // Execute the query
        healthStore.execute(query)
    }
    
    func calculateWeeklySummary() {
            let startDate = Date().startOfWeek()
            
            fetchRunningWorkouts(startDate: startDate) { runningDataArray in
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
                DispatchQueue.main.async {
                    self.weeklyRunDistance = totalDistance.rounded(toPlaces: 2)
                    self.weeklyRunTime = totalDuration.rounded(toPlaces: 2)
                    self.weeklyRunPace = averagePace.rounded(toPlaces: 2)
                    self.weeklyRunSummery = weeklyRunData
                    self.formattedRunTime = runTimeFormatted
                    self.formattedRunPace = runPaceFormatted
                    
                }
            }
        }
}


//chart data
extension HealthManager {
    
    func oneWeekData(){
        //for the graph on first page
        fetchWeeklyInfo(startDate: Date().startOfYear()){
            yearDistance in
            DispatchQueue.main.async {
                self.weeklyRunSummery = yearDistance
      
            }
        }
    }
    
    //fetches all workouts at the start so it loads at the same time
    func lottaRuns() {
        fetchRunningWorkouts(startDate: Date().startOfYear()) { runningData in
            DispatchQueue.main.async {
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
