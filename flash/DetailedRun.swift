//
//  DetailedRun.swift
//  flash
//
//  Created by abbe on 2024-05-17.
//

import SwiftUI
import CoreLocation
import MapKit


//view when pressing on a run
struct DetailedRun: View {
    @EnvironmentObject private var manager: HealthManager
    let workout: RunningData
    @State private var displayedWorkout: RunningData
    @State private var region: MKCoordinateRegion
    @State private var isLoadingDetails = false
        
        init(workout: RunningData) {
            self.workout = workout
            _displayedWorkout = State(initialValue: workout)
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
            Text(displayedWorkout.date.formatted(.dateTime
                .day(.defaultDigits)
                .month(.wide)
                .weekday(.wide)))
                .font(Font.custom("CallingCode-Regular", size: 40))
            
           MapView(route: displayedWorkout.route, region: $region)
                           .frame(height: 300) // Adjust the height as needed

            if isLoadingDetails {
                HStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text("Loading workout details...")
                        .font(Font.custom("CallingCode-Regular", size: 14))
                }
            }
            
            Text("Distance: \(displayedWorkout.distance / 1000, specifier: "%.2f") km")
                .font(Font.custom("CallingCode-Regular", size: 20))
            Text("Duration: \(displayedWorkout.formatDuration)")
                .font(Font.custom("CallingCode-Regular", size: 20))
            Text("Average Pace: \(displayedWorkout.formattedPace)")
                .font(Font.custom("CallingCode-Regular", size: 20))
            
            HStack{
                VStack{
                    Text("Calories")
                    Text("\(displayedWorkout.activeCalories, specifier: "%.2f")")
                }.frame(width: 100)
              
                VStack{
                    Text("Heart rate")
                    Text(metricText(displayedWorkout.heartRate))
                }.frame(width: 100)
            }.font(Font.custom("CallingCode-Regular", size: 20))
                //.frame(alignment: .trailing)
            HStack{
                VStack{
                    Text("Cadence")
                    Text(metricText(displayedWorkout.cadence))
                }.frame(width: 100)
              
                VStack{
                    Text("Elevation")
                    Text(metricText(displayedWorkout.elevation))
                }.frame(width: 100)
            }.font(Font.custom("CallingCode-Regular", size: 20))
                //.frame(alignment: .trailing)
            
            Spacer()
            NavigationLink(destination: statsView(workout: displayedWorkout), label: {
                Text("advanced stats")
                    .font(Font.custom("CallingCode-Regular", size: 20))
                    .frame(width: 250, height: 20, alignment: .center)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                
            })
            .disabled(isLoadingDetails)
            .opacity(isLoadingDetails ? 0.5 : 1)
        }
        .font(Font.custom("CallingCode-Regular", size: 70))
        .padding()
        .navigationTitle("Workout Details")
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        
        .onAppear {
            setRegionToFitRoute()
            Task {
                await loadWorkoutDetailsIfNeeded()
            }
        }
    }

    private func metricText(_ value: Double) -> String {
        value > 0 ? String(format: "%.2f", value) : "N/A"
    }

    private func loadWorkoutDetailsIfNeeded() async {
        guard !isLoadingDetails,
              displayedWorkout.route.isEmpty,
              displayedWorkout.heartRateData.isEmpty,
              displayedWorkout.cadenceData.isEmpty,
              displayedWorkout.pacePerKM.isEmpty else {
            return
        }

        await MainActor.run {
            isLoadingDetails = true
        }

        let hydratedWorkout = await manager.hydrateRunDetails(displayedWorkout)

        await MainActor.run {
            displayedWorkout = hydratedWorkout
            isLoadingDetails = false
            setRegionToFitRoute()
        }
    }
    
    private func setRegionToFitRoute() {
        guard !displayedWorkout.route.isEmpty else { return }
        
        var minLat = displayedWorkout.route.first!.coordinate.latitude
        var maxLat = displayedWorkout.route.first!.coordinate.latitude
        var minLon = displayedWorkout.route.first!.coordinate.longitude
        var maxLon = displayedWorkout.route.first!.coordinate.longitude
        
        for location in displayedWorkout.route {
            let coordinate = location.coordinate
            if coordinate.latitude < minLat { minLat = coordinate.latitude }
            if coordinate.latitude > maxLat { maxLat = coordinate.latitude }
            if coordinate.longitude < minLon { minLon = coordinate.longitude }
            if coordinate.longitude > maxLon { maxLon = coordinate.longitude }
        }
        
        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        let spanLat = (maxLat - minLat) * 1.2
        let spanLon = (maxLon - minLon) * 1.2
        
        region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            span: MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLon)
        )
    }

}
