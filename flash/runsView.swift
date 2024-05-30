//
//  runsView.swift
//  flash
//
//  Created by abbe on 2024-04-16.
//

import SwiftUI
import CoreLocation
import HealthKit

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
                NavigationLink(destination: DetailedRun(workout:    workout)) {
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

