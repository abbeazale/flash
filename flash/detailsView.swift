//
//  detailsView.swift
//  flash
//
//  Created by abbe on 2024-11-21.
//

import SwiftUI

struct detailsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var manager: HealthManager
    
    // Calculate yearly stats
    private var yearlyStats: (distance: Double, duration: TimeInterval, pace: Double) {
        let runs = manager.allRuns
        let totalDistance = runs.reduce(0.0) { $0 + $1.distance } / 1000 // Convert to km
        let totalDuration = runs.reduce(0.0) { $0 + $1.duration }
        let averagePace = totalDuration / 60 / totalDistance // Convert to min/km
        
        return (totalDistance, totalDuration, averagePace)
    }
    
    var body: some View {
        ZStack{
            Color(red: 54 / 255, green: 46 / 255, blue: 64/255)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                VStack{
                    
                    Text(formatDuration(yearlyStats.duration))
                        .frame(maxWidth: 300, alignment: .leading)
                    Text("Time")
                        .frame(maxWidth: 300, alignment: .leading)
                    
                    Text(formatPace(yearlyStats.pace))
                        .frame(maxWidth: 300, alignment: .leading)
                        .padding(.top, 3)
                    Text("Average Pace")
                        .frame(maxWidth: 300, alignment: .leading)
                    
                    Text(String(format: "%.2f km", yearlyStats.distance))
                        .frame(maxWidth: 300, alignment: .leading)
                        .padding(.top, 3)
                    Text("Total Distance")
                        .frame(maxWidth: 300, alignment: .leading)
                }
                .font(Font.custom("CallingCode-Regular", size: 18))
                .padding(.top, 30)
                .padding(.horizontal)
                
                Spacer()
    
                VStack(spacing: 15) {
                    NavigationLink {
                        RunListPage(
                            title: "Longest Runs",
                            runs: manager.allRuns.sorted { $0.distance > $1.distance },
                            metric: { run in
                                String(format: "%.2f km", run.distance / 1000)
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
                                    let pace1 = paceToSeconds(first.formattedPace)
                                    let pace2 = paceToSeconds(second.formattedPace)
                                    return pace1 < pace2
                                },
                            metric: { $0.formattedPace }
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
            .padding()
            .foregroundColor(.white)
        }
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
    
    // Helper function to format duration
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    // Helper function to format pace
    private func formatPace(_ pace: Double) -> String {
        guard pace.isFinite && !pace.isNaN else {
            return "N/A"
        }
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d:%02d/km", minutes, seconds)
    }
    
    // Helper function to convert pace string to seconds for sorting
    private func paceToSeconds(_ paceString: String) -> Double {
        let components = paceString.split(separator: ":")
        if components.count == 2,
           let minutes = Double(components[0]),
           let seconds = Double(components[1].prefix(2)) {
            return minutes * 60 + seconds
        }
        return Double.infinity
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
