//
//  runsView.swift
//  flash
//
//  Created by abbe on 2024-04-16.
//

import SwiftUI
import HealthKit
import SwiftData


struct runsView: View {
    @EnvironmentObject var manager: HealthManager
    @Query private var profiles: [RunnerProfile]
    @State private var hasLoadedInitialData = false
    @State private var scrollPosition: UUID?

    private var unitPresentation: RunUnitPresentation {
        RunUnitPresentation(
            unit: profiles.first { $0.key == RunnerProfile.singletonKey }?.distanceUnit
                ?? .kilometers
        )
    }
    
    var body: some View {
        ZStack{
            Color.flashBackground
                .ignoresSafeArea()
            VStack{
                Text("runs")
                    .font(Font.custom("CallingCode-Regular", size: 70))
                //scroll view to scroll through workouts but keep the run at the top
                ScrollView(.vertical){
                    LazyVStack{
                        //put array is desending order
                        ForEach(manager.allRuns) { workout in
                            NavigationLink(destination: DetailedRun(workout: workout)) {
                                HStack {
                                    Text(workout.date.formatted(.dateTime
                                        .day(.defaultDigits)
                                        .month(.wide)
                                        .weekday(.wide)))
                                    .font(.headline)
                                    Text(
                                        unitPresentation.distanceText(
                                            fromMeters: workout.distance
                                        )
                                    )
                                        .font(.subheadline)
                                }
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(8)
                            }
                            .id(workout.id) // Important for scroll position tracking
                            .onAppear {
                                // Auto-load more when approaching the end
                                if workout.id == manager.allRuns.last?.id {
                                    Task {
                                        await manager.loadMoreRuns()
                                    }
                                }
                            }
                        }
                        
                        // Loading indicator at bottom
                        if manager.isLoadingMore {
                            HStack {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("Loading more...")
                                    .font(.subheadline)
                            }
                            .padding()
                        }
                    }
                }
                .onAppear {
                    // Only load data once on first appearance
                    if !hasLoadedInitialData && manager.allRuns.isEmpty {
                        Task {
                            await manager.lottaRuns()
                            hasLoadedInitialData = true
                        }
                    }
                }
                
            }.foregroundColor(.white)
        }
    }
}
