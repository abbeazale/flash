//
//  ContentView.swift
//  flash
//
//  Created by abbe on 2024-04-05.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var manager: HealthManager

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 54 / 255, green: 46 / 255, blue: 64/255)
                
                // Show content immediately (with cached data if available)
                VStack {
                    HStack {
                        NavigationLink(destination: detailsView(), label: {
                            Image(systemName: "gearshape")
                                .padding(.leading, 30)
                        })
                        Spacer()
                        Text("swipe to start a run")
                        Spacer()
                        NavigationLink(destination: runsView(), label: {
                            Image(systemName: "list.bullet")
                                .padding(.trailing, 30)
                        })
                    }
                    .opacity(0.30)
                    .padding(.top, -10)
                    
                    WeeklySummery(stats: Stats(
                        totalKm: manager.weeklyRunDistance,
                        totalTime: manager.formattedRunTime,
                        averagePace: manager.weeklyRunPace,
                        formattPace: manager.formattedRunPace
                    ))
                    
                    ChartsView()
                    
                    // Show subtle loading indicator if still loading
                    if manager.isLoading {
                        HStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.7)
                            Text("Updating...")
                                .font(.caption)
                                .opacity(0.6)
                        }
                        .padding(.top, 10)
                    }
                }
            }
            .ignoresSafeArea(.all)
            .foregroundColor(.white)
        }
    }
}
