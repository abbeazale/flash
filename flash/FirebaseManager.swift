//
//  FirebaseManager.swift
//  flash
//
//  Created by abbe on 2024-05-25.
//

import Foundation
import Firebase
import FirebaseFirestore
import CoreLocation


class FirebaseManager {
    
    private let storage = Firestore.firestore()
    
    func saveRunningData(_ runningData: RunningData) async {
        do {
            // 1. Create unique ID from date and distance
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm"
            let uniqueId = "\(dateFormatter.string(from: runningData.date))-\(String(format: "%.2f", runningData.distance))"
            
            // 2. Convert route data
            let routeData: [[String:Double]] = runningData.route.map { location in
                [
                    "latitude": location.coordinate.latitude,
                    "longitude": location.coordinate.longitude,
                    "altitude": location.altitude
                ]
            }
            
            // 3. Convert pace data
            let pacePerKMData: [[String: Any]] = runningData.pacePerKM.map { segment in
                [
                    "kilometer": segment.kilometer,
                    "pace": segment.pace,
                    "formattedPace": segment.formattedPace
                ]
            }
            
            // 4. Prepare data dictionary
            let data: [String: Any] = [
                "id": runningData.id.uuidString,
                "date": runningData.date,
                "distance": runningData.distance,
                "cadence": runningData.cadence,
                "power": runningData.power,
                "pace": runningData.pace,
                "formattedPace": runningData.formattedPace,
                "heartRate": runningData.heartRate,
                "strideLength": runningData.strideLength,
                "verticalOscillation": runningData.verticalOscillation,
                "groundContactTime": runningData.groundContactTime,
                "duration": runningData.duration,
                "formattedDuration": runningData.formattedDuration,
                "elevation": runningData.elevation,
                "activeCalories": runningData.activeCalories,
                "route": routeData,
                "pacePerKM": pacePerKMData,
                "formatDuration": runningData.formattedDuration
            ]
            
            // 5. Check for existing document and save
            let docRef = storage.collection("collection").document(uniqueId)
            let docSnapshot = try await docRef.getDocument()
            
            if docSnapshot.exists {
                print("Run already exists with ID: \(uniqueId), skipping save")
                return
            }
            
            // 6. Save the document with the unique ID
            try await docRef.setData(data)
            print("Running data successfully saved with ID: \(uniqueId)")
            
        } catch {
            print("Error saving running data: \(error.localizedDescription)")
        }
    }
    
    //fetch running data from the database
    func fetchRunningData() async -> [RunningData] {
        do {
            let snapshot = try await storage.collection("collection")
                .order(by: "date", descending: true)
                .getDocuments()
            
            return snapshot.documents.compactMap { document -> RunningData? in
                let data = document.data()
                
                // Extract and validate required data
                guard let idString = data["id"] as? String,
                      let id = UUID(uuidString: idString),
                      let date = (data["date"] as? Timestamp)?.dateValue(),
                      let distance = data["distance"] as? Double,
                      let cadence = data["cadence"] as? Double,
                      let power = data["power"] as? Double,
                      let pace = data["pace"] as? Double,
                      let formattedPace = data["formattedPace"] as? String,
                      let heartRate = data["heartRate"] as? Double,
                      let strideLength = data["strideLength"] as? Double,
                      let verticalOscillation = data["verticalOscillation"] as? Double,
                      let groundContactTime = data["groundContactTime"] as? Double,
                      let duration = data["duration"] as? Double,
                      let formattedDuration = data["formattedDuration"] as? String,
                      let elevation = data["elevation"] as? Double,
                      let activeCalories = data["activeCalories"] as? Double,
                      let routeData = data["route"] as? [[String: Double]],
                      let formatDuration = data["formatDuration"] as? String,
                      let pacePerKMData = data["pacePerKM"] as? [[String: Any]]
                else {
                    print("Failed to parse document: \(document.documentID)")
                    return nil
                }
                
                // Convert route data to CLLocation array
                let route: [CLLocation] = routeData.compactMap { locationData in
                    guard let latitude = locationData["latitude"],
                          let longitude = locationData["longitude"],
                          let altitude = locationData["altitude"] else {
                        return nil
                    }
                    
                    let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                    return CLLocation(
                        coordinate: coordinate,
                        altitude: altitude,
                        horizontalAccuracy: kCLLocationAccuracyBest,
                        verticalAccuracy: kCLLocationAccuracyBest,
                        timestamp: Date()
                    )
                }
                
                // Convert pace data to SegmentPace array
                let pacePerKM: [SegmentPace] = pacePerKMData.compactMap { segmentData in
                    guard let kilometer = segmentData["kilometer"] as? Int,
                          let pace = segmentData["pace"] as? Double,
                          let formattedPace = segmentData["formattedPace"] as? String else {
                        return nil
                    }
                    return SegmentPace(kilometer: kilometer, pace: pace, formattedPace: formattedPace)
                }
                
                // Create and return RunningData object
                return RunningData(
                    date: date,
                    distance: distance,
                    cadence: cadence,
                    power: power,
                    pace: pace,
                    formattedPace: formattedPace,
                    heartRate: heartRate,
                    strideLength: strideLength,
                    verticalOscillation: verticalOscillation,
                    groundContactTime: groundContactTime,
                    duration: duration,
                    formattedDuration: formattedDuration,
                    elevation: elevation,
                    activeCalories: activeCalories,
                    route: route,
                    formatDuration: formatDuration,
                    pacePerKM: pacePerKM
                )
            }
            
        } catch {
            print("Error fetching running data: \(error.localizedDescription)")
            return []
        }
    }
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
