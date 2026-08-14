//
//  detailsView.swift
//  flash
//
//  Created by abbe on 2024-11-21.
//

import SwiftData
import SwiftUI

struct detailsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var manager: HealthManager
    @Query(sort: \CachedRunSummary.date) private var cachedRuns: [CachedRunSummary]
    @Query private var profiles: [RunnerProfile]
    
    private var allTimeTotals: RunTotals {
        RunAggregator.totals(cachedRuns.map(\.aggregateData))
    }

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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                VStack{
                    
                    Text(RunUnitPresentation.durationText(allTimeTotals.duration))
                        .frame(maxWidth: 300, alignment: .leading)
                    Text("Time")
                        .frame(maxWidth: 300, alignment: .leading)
                    
                    Text(unitPresentation.paceText(fromMinutesPerKilometer: allTimeTotals.avgPace))
                        .frame(maxWidth: 300, alignment: .leading)
                        .padding(.top, 3)
                    Text("Average Pace")
                        .frame(maxWidth: 300, alignment: .leading)
                    
                    Text(unitPresentation.distanceText(fromMeters: allTimeTotals.distance))
                        .frame(maxWidth: 300, alignment: .leading)
                        .padding(.top, 3)
                    Text("Total Distance")
                        .frame(maxWidth: 300, alignment: .leading)
                }
                .font(Font.custom("CallingCode-Regular", size: 18))
                .padding(.top, 30)
                .padding(.horizontal)
                
                VStack(spacing: 15) {
                    NavigationLink {
                        PRView()
                    } label: {
                        Text("Personal Records")
                            .font(Font.custom("CallingCode-Regular", size: 24))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                    }

                    NavigationLink {
                        TrendsView()
                    } label: {
                        Text("Trends")
                            .font(Font.custom("CallingCode-Regular", size: 24))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                    }

                    NavigationLink {
                        RunListPage(
                            title: "Longest Runs",
                            runs: manager.allRuns.sorted { $0.distance > $1.distance },
                            metric: { run in
                                unitPresentation.distanceText(fromMeters: run.distance)
                            }
                        )
                    } label: {
                        Text("Longest Runs")
                            .font(Font.custom("CallingCode-Regular", size: 24))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                    }

                    NavigationLink {
                        RunListPage(
                            title: "Fastest Runs",
                            runs: manager.allRuns
                                .filter { $0.distance >= 1000 } // Only runs ≥ 1 km
                                .sorted { first, second in
                                    let pace1 = paceMinutesPerKilometer(for: first)
                                    let pace2 = paceMinutesPerKilometer(for: second)
                                    return pace1 < pace2
                                },
                            metric: { run in
                                unitPresentation.paceText(
                                    fromMinutesPerKilometer: paceMinutesPerKilometer(for: run)
                                )
                            }
                        )
                    } label: {
                        Text("Fastest Runs")
                            .font(Font.custom("CallingCode-Regular", size: 24))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                    }

                    NavigationLink {
                        RunListPage(
                            title: "Most Calories Burned",
                            runs: manager.allRuns.sorted { $0.activeCalories > $1.activeCalories },
                            metric: { run in
                                String(format: "%.0f cal", run.activeCalories)
                            }
                        )
                    } label: {
                        Text("Most Calories Burned")
                            .font(Font.custom("CallingCode-Regular", size: 24))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
                }
            }
            .padding()
            .foregroundColor(.white)
        }
        .toolbarBackground(Color.flashBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
    
    private func paceMinutesPerKilometer(for run: RunningData) -> Double {
        guard run.distance.isFinite,
              run.duration.isFinite,
              run.distance > 0,
              run.duration > 0 else {
            return .infinity
        }
        return (run.duration / 60) / (run.distance / 1_000)
    }
}

struct RunListSheet: View {
    @Environment(\.dismiss) var dismiss
    let title: String
    let runs: [RunningData]
    let metric: (RunningData) -> String
    
    var body: some View {
        NavigationView {
            List(runs) { run in
                NavigationLink(destination: DetailedRun(workout: run)) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(run.date.formatted(.dateTime
                                .day(.defaultDigits)
                                .month(.wide)
                                .weekday(.wide)))
                            .font(Font.custom("CallingCode-Regular", size: 16))
                        }
                        Spacer()
                        Text(metric(run))
                            .font(Font.custom("CallingCode-Regular", size: 16))
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
