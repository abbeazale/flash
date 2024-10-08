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
    
    func saveRunningData(_ runningData: RunningData){
        //convert cllocation to an array of dictionaries
        var routeData: [[String:Double]] = []
        for location in runningData.route {
            let locationData: [String: Double] = [
                "latitude": location.coordinate.latitude,
                "longitude": location.coordinate.longitude,
                "altitude": location.altitude
            ]
            routeData.append(locationData)
        }
        let pacePerKMData: [[String: Any]] = runningData.pacePerKM.map { segment in
                    [
                        "kilometer": segment.kilometer,
                        "pace": segment.pace,
                        "formattedPace": segment.formattedPace
                    ]
                }
        
        // Prepare data dictionary to be saved to Firestore
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
        
        //code below is to not add
        let dateToCheck = runningData.date
        let storage = Firestore.firestore()

        // Convert the date to a range to account for runs on the same day (ignore time)
        let startOfDay = Calendar.current.startOfDay(for: dateToCheck)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!

        let query = storage.collection("collections")
            .whereField("date", isGreaterThanOrEqualTo: startOfDay)
            .whereField("date", isLessThan: endOfDay)

        query.getDocuments { (querySnapshot, error) in
            if let error = error {
                print("Error checking for duplicate runs: \(error.localizedDescription)")
            } else if let documents = querySnapshot?.documents, !documents.isEmpty {
                print("Run data for this date already exists. Skipping save.")
            } else {
                // No duplicate found, safe to add the new run
                storage.collection("collections").document().setData(data) { error in
                    if let error = error {
                        print("Error saving running data: \(error.localizedDescription)")
                    } else {
                        print("Running data successfully saved!")
                    }
                }
            }
        }
    }
    
    
    //fetch running data from the database
    func fetchRunningData(completion: @escaping([RunningData]) -> Void){
        //get runs from the collection
        storage.collection("collections").getDocuments {
            snapshot, error in
            if let error = error {
                print("Error fetching running data: \(error.localizedDescription)")
                completion([])
                return
            }
            
            guard let documents = snapshot?.documents else {
                 print("No documents found")
                 completion([])
                 return
             }
            
            var runningDataArray: [RunningData] = []
            
            for document in documents {
                let data = document.data()
                // Safely unwrap and convert document data to RunningData properties
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
                    continue
                }
                
                // Convert route data back to an array of CLLocation
                var route: [CLLocation] = []
                for locationData in routeData {
                  if let latitude = locationData["latitude"],
                     let longitude = locationData["longitude"],
                     let altitude = locationData["altitude"] {
                      
                      let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                      let location = CLLocation(coordinate: coordinate, altitude: altitude, horizontalAccuracy: kCLLocationAccuracyBest, verticalAccuracy: kCLLocationAccuracyBest, timestamp: Date())
                      route.append(location)
                  }
                }
                
                let pacePerKM: [SegmentPace] = pacePerKMData.compactMap { segmentData in
                    guard let kilometer = segmentData["kilometer"] as? Int,
                          let pace = segmentData["pace"] as? Double,
                          let formattedPace = segmentData["formattedPace"] as? String else {
                        return nil
                    }
                    return SegmentPace(kilometer: kilometer, pace: pace, formattedPace: formattedPace)
                }
                // Create RunningData object from Firestore document data
                let runningData = RunningData(
                   
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
                
                // Append the created RunningData object to the array
                runningDataArray.append(runningData)
            }
            // Pass the array of RunningData objects to the completion handler
            completion(runningDataArray)
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
