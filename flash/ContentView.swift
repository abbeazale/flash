//
//  ContentView.swift
//  flash
//
//  Created by abbe on 2024-04-05.
//

import OSLog
import SwiftData
import SwiftUI

private let historySyncLogger = Logger(subsystem: "abbe.ca.flash", category: "HistorySync")

struct ContentView: View {
    @EnvironmentObject var manager: HealthManager
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            ZStack {
                Color.flashBackground
                
                // Show content immediately (with cached data if available)
                VStack {
                    HStack {
                        NavigationLink(destination: SettingsView(), label: {
                            Image(systemName: "gearshape")
                                .padding(.leading, 30)
                        })
                        .accessibilityLabel("Settings")
                        Spacer()
                        Text("swipe to start a run")
                        Spacer()
                        HStack(spacing: 18) {
                            NavigationLink(destination: detailsView(), label: {
                                Image(systemName: "chart.xyaxis.line")
                            })
                            .accessibilityLabel("Analytics")

                            NavigationLink(destination: runsView(), label: {
                                Image(systemName: "list.bullet")
                            })
                            .accessibilityLabel("Run history")
                        }
                        .padding(.trailing, 30)
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
            .task(id: manager.healthKitAuthorizationFinished) {
                guard HistorySyncLaunchGate.shouldRun(
                    authorizationFinished: manager.healthKitAuthorizationFinished,
                    authorizationSucceeded: manager.healthKitAuthorizationSucceeded
                ) else { return }

                let store = HistoryStore(context: modelContext)
                do {
                    try await store.backfillIfNeeded()
                    try await store.sync()
                } catch {
                    historySyncLogger.error(
                        "History sync failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }
    }
}

extension Color {
    /// Shared app background. Used for screen backgrounds and the navigation bar
    /// so the top safe area blends in instead of showing a black strip on scroll.
    static let flashBackground = Color(red: 54 / 255, green: 46 / 255, blue: 64 / 255)
}
