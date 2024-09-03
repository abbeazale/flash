//
//  model.swift
//  flash
//
//  Created by abbe on 2024-08-17.
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

struct SegmentPace {
    let kilometer: Int
    let pace: Double
    let formattedPace: String
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
    let pacePerKM: [SegmentPace]
}


struct Stats {
    let id = UUID()
    let totalKm: Double
    let totalTime: String
    let averagePace: Double
    let formattPace: String

}
