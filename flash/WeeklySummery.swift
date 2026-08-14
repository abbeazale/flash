//
//  SwiftUIView.swift
//  flash
//
//  Created by abbe on 2024-04-12.
//

import SwiftData
import SwiftUI



struct WeeklySummery: View {
    @EnvironmentObject var manager: HealthManager
    @Query private var profiles: [RunnerProfile]
    @State var stats: Stats

    private var unitPresentation: RunUnitPresentation {
        RunUnitPresentation(
            unit: profiles.first { $0.key == RunnerProfile.singletonKey }?.distanceUnit
                ?? .kilometers
        )
    }

//weekly run summery array of data 

    var body: some View {
            VStack{
               
                Text(
                    "\(unitPresentation.distance(fromMeters: manager.weeklyRunDistance * 1_000), specifier: "%.2f")"
                )
                    .font(Font.custom("CallingCode-Regular", size: 96))
                Text(unitPresentation.unit.title.lowercased())
                    .font(Font.custom("CallingCode-Regular", size: 16))
                    .opacity(0.30)
                VStack{
                    Text(String(manager.formattedRunTime))
                        .frame(maxWidth: 300, alignment: .leading)
                    Text("time")
                        .frame(maxWidth: 300, alignment: .leading)
                    
                    Text(
                        unitPresentation.paceText(
                            fromMinutesPerKilometer: manager.weeklyRunPace
                        )
                    )
                        .frame(maxWidth: 300, alignment: .leading)
                        .padding(.top, 3)
                    Text("average pace")
                        .frame(maxWidth: 300, alignment: .leading)
                    
                }.font(Font.custom("CallingCode-Regular", size: 18))
                    .padding(.top, 30)
                
            }.padding(.bottom, 100)
        
    }
}
