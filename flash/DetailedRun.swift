//
//  DetailedRun.swift
//  flash
//
//  Created by abbe on 2024-05-17.
//

import SwiftUI
import CoreLocation
import MapKit

struct DetailedRun: View {
    let workout: RunningData
    @State private var region: MKCoordinateRegion
        
        init(workout: RunningData) {
            self.workout = workout
            if let firstLocation = workout.route.first {
                _region = State(initialValue: MKCoordinateRegion(
                    center: firstLocation.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))
            } else {
                _region = State(initialValue: MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // Default coordinates
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))
            }
        }
    

    var body: some View {
        VStack(spacing: 10) {
            Text(workout.date.formatted(.dateTime
                .day(.defaultDigits)
                .month(.wide)
                .weekday(.wide)))
                .font(Font.custom("CallingCode-Regular", size: 40))
            
           MapView(route: workout.route, region: $region)
                           .frame(height: 300) // Adjust the height as needed
            
            Text("Distance: \(workout.distance / 1000, specifier: "%.2f") km")
                .font(Font.custom("CallingCode-Regular", size: 20))
            Text("Duration: \(workout.formatDuration)")
                .font(Font.custom("CallingCode-Regular", size: 20))
            Text("Average Pace: \(workout.formattedPace)")
                .font(Font.custom("CallingCode-Regular", size: 20))
            
            HStack{
                VStack{
                    Text("Calories")
                    Text("\(workout.activeCalories, specifier: "%.2f")")
                }.frame(width: 100)
              
                VStack{
                    Text("Heart rate")
                    Text("\(workout.heartRate, specifier: "%.2f")")
                }.frame(width: 100)
            }.font(Font.custom("CallingCode-Regular", size: 20))
                //.frame(alignment: .trailing)
            HStack{
                VStack{
                    Text("Cadence")
                    Text("\(workout.cadence, specifier: "%.2f")")
                }.frame(width: 100)
              
                VStack{
                    Text("Elevation")
                    Text("\(workout.elevation, specifier: "%.2f")")
                }.frame(width: 100)
            }.font(Font.custom("CallingCode-Regular", size: 20))
                //.frame(alignment: .trailing)
            
            Spacer()
            NavigationLink(destination: statsView(workout: workout), label: {
                Text("advanced stats")
                    .font(Font.custom("CallingCode-Regular", size: 20))
                    .frame(width: 250, height: 20, alignment: .center)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                
            })
        }
        .font(Font.custom("CallingCode-Regular", size: 70))
        .padding()
        .navigationTitle("Workout Details")
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        
        .onAppear {
            setRegionToFitRoute()
        }
    }
    
    private func setRegionToFitRoute() {
        guard !workout.route.isEmpty else { return }
        
        var minLat = workout.route.first!.coordinate.latitude
        var maxLat = workout.route.first!.coordinate.latitude
        var minLon = workout.route.first!.coordinate.longitude
        var maxLon = workout.route.first!.coordinate.longitude
        
        for location in workout.route {
            let coordinate = location.coordinate
            if coordinate.latitude < minLat { minLat = coordinate.latitude }
            if coordinate.latitude > maxLat { maxLat = coordinate.latitude }
            if coordinate.longitude < minLon { minLon = coordinate.longitude }
            if coordinate.longitude > maxLon { maxLon = coordinate.longitude }
        }
        
        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        let spanLat = (maxLat - minLat) * 1.2 // Add some padding
        let spanLon = (maxLon - minLon) * 1.2 // Add some padding
        
        region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            span: MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLon)
        )
    }

}


