//
//  runsView.swift
//  flash
//
//  Created by abbe on 2024-04-16.
//

import SwiftUI
import HealthKit


struct runsView: View {
    @EnvironmentObject var manager: HealthManager
    var body: some View {
        VStack{
            Text("runs")
                .font(Font.custom("CallingCode-Regular", size: 70))
            //scroll view to scroll through workouts but keep the run at the top
            ScrollView(.vertical){
                VStack{
                    //put array is desending order
                    ForEach(manager.allRuns) { workout in
                NavigationLink(destination: DetailedRun(workout: workout)) {
                            HStack {
                                Text(workout.date.formatted(.dateTime
                                    .day(.defaultDigits)
                                    .month(.wide)
                                    .weekday(.wide)))
                                    .font(.headline)
                                Text("\(workout.distance / 1000, specifier: "%.2f") km")
                                    .font(.subheadline)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                        }
                    }
                }
            }.task {
                await manager.lottaRuns()
            }
        
        }.foregroundColor(.white)
    }
}

