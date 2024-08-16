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
        
        let runDocument = storage.collection("workouts").document(runningData.id.uuidString)
        runDocument.getDocument { (document, error) in
            if let document = document, document.exists {
                print("Run data already exists in the database. Skipping save.")
            } else {
                runDocument.setData(data) { error in
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
        storage.collection("workouts").getDocuments {
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
