//
//  runsView.swift
//  flash
//
//  Created by abbe on 2024-04-16.
//

import SwiftUI
import CoreLocation
import HealthKit
import Foundation

struct CodableLocation: Codable {
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var timestamp: Date

    init(location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.altitude = location.altitude
        self.timestamp = location.timestamp
    }

    var location: CLLocation {
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: altitude,
            horizontalAccuracy: kCLLocationAccuracyBest,
            verticalAccuracy: kCLLocationAccuracyBest,
            timestamp: timestamp
        )
    }
}

struct RunningData: Identifiable {
    let id = UUID()
    let date: Date
    let distance: Double // in meters
    let cadence: Double // in steps per minute
    let power: Double // in watts
    let pace: Double // in minutes per kilometer
    let formattedPace: String // formatted pace in minutes:seconds / km
    let heartRate: Double // in beats per minute
    let strideLength: Double // in meters
    let verticalOscillation: Double // in centimeters
    let groundContactTime: Double // in milliseconds
    let duration: TimeInterval
    let formattedDuration: String // formatted duration in hours:minutes:seconds
    let elevation: Double // in meters
    let activeCalories: Double // in kilocalories
    let route: [CLLocation] // Route locations
    let formatDuration: String
   
}

struct runsView: View {
    @EnvironmentObject var manager: HealthManager
    var body: some View {
        VStack{
            Text("runs")
                .font(Font.custom("CallingCode-Regular", size: 70))
            //scroll view to scroll through workouts but keep the run at the top
            ScrollView(.vertical){
                VStack{
                    //put array is desending order
                    ForEach(manager.allRuns) { workout in
                NavigationLink(destination: DetailedRun(workout: workout)) {
                            HStack {
                                Text(workout.date.formatted(.dateTime
                                    .day(.defaultDigits)
                                    .month(.wide)
                                    .weekday(.wide)))
                                    .font(.headline)
                                Text("\(workout.distance / 1000, specifier: "%.2f") km")
                                    .font(.subheadline)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                        }
                    }
                }
            }.onAppear {
                manager.fetchRunningWorkoutsFirestore()
            }
        
        }.foregroundColor(.white)
    }
}

extension RunningData {
    func pacePerKM() -> [(kilometer: Int, pace: Double, formattedPace: String)]{
        // If the total distance is less than 1 km, return the total pace as a single segment
        guard !route.isEmpty else {
            let pace = duration / (distance / 1000)
            let formattedPace = String(format: "%d:%02d", Int(pace), Int((pace - Double(Int(pace)))*60))
            return [(kilometer: 1, pace: pace, formattedPace: formattedPace)]
        }
        
        //segments array
        var segments: [(kilometer: Int, pace: Double, formattedPace: String)] = []
        var currentKM = 1
        var segmentDistance: Double = 0
        var segmentTime: TimeInterval = 0
        var lastLocation: CLLocation? = nil
        //var lastTime: Date? = nil
        
        //loop through all the locations from the route
        for location in route {
            if let lastLocation = lastLocation {
                let distanceBetween = location.distance(from: lastLocation)
                let timeBetween = location.timestamp.timeIntervalSince(lastLocation.timestamp)
                segmentDistance += distanceBetween
                segmentTime += timeBetween
                
                if(segmentDistance >= 1000 ){
                    //gets the pace in minutes per km
                    let pace = (segmentTime / (segmentDistance / 100)) / 60
                    let formatPace = String(format: "%02d:%02d", Int(pace), Int((pace - Double(Int(pace))) * 60))
                    print("segment distance")
                    print(segmentDistance)
                    print("pace")
                    print(formatPace)
                    segments.append((kilometer: currentKM, pace: pace, formattedPace: formatPace))
                    currentKM += 1
                    segmentDistance -= 1000
                    segmentTime *= (segmentDistance / distanceBetween) * timeBetween
                }
            }
            
            lastLocation = location
            
        }
        
        ///the last remaining segment...
        if segmentDistance > 0 {
            let pace = (segmentTime / (segmentDistance / 1000 )) / 60
            let formattedPace = String(format: "%d:%02d", Int(pace), Int((pace - Double(Int(pace))) * 60))
            segments.append((kilometer: currentKM, pace: pace, formattedPace: formattedPace))
        }
        
        //print("segments")
        //print(segments)
        return segments
    }
    
    
    ///if pace is already calculated
    func formatPace(_ pace: Double) -> String {
        guard pace.isFinite && !pace.isNaN else {
            return "N/A"
        }

        let totalSeconds = pace * 60 // pace in seconds per km
        let minutes = Int(totalSeconds) / 60
        let seconds = Int(totalSeconds) % 60
        return String(format: "%0d:%02d / km", minutes, seconds)
    }
    
}
