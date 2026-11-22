//
//  SwiftUIView.swift
//  flash
//
//  Created by abbe on 2024-04-12.
//

import SwiftData
import SwiftUI



struct WeeklySummery: View {
    let summary: WeekSummary
    /// The selected day. 0 is Monday. nil shows the whole week.
    var selectedDay: Int? = nil
    @Query private var profiles: [RunnerProfile]

    private var unitPresentation: RunUnitPresentation {
        RunUnitPresentation(
            unit: profiles.first { $0.key == RunnerProfile.singletonKey }?.distanceUnit
                ?? .kilometers
        )
    }

    private var totals: WeekTotals {
        selectedDay.map { summary.totals(forDay: $0) } ?? summary.totals
    }

    /// "kilometers", or "kilometers · wed, nov 19" when a day is selected.
    private var unitLabel: String {
        let unit = unitPresentation.unit.title.lowercased()
        let days = summary.days()
        guard let selectedDay, days.indices.contains(selectedDay) else { return unit }
        let day = days[selectedDay].formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(unit) · \(day.lowercased())"
    }

    var body: some View {
            VStack{
               
                Text(
                    "\(unitPresentation.distance(fromMeters: totals.kilometers * 1_000), specifier: "%.2f")"
                )
                    .font(Font.custom("CallingCode-Regular", size: 96))
                    .contentTransition(.numericText())
                Text(unitLabel)
                    .font(Font.custom("CallingCode-Regular", size: 16))
                    .opacity(selectedDay == nil ? 0.30 : 1)
                VStack{
                    Text(totals.formattedDuration)
                        .frame(maxWidth: 300, alignment: .leading)
                    Text("time")
                        .frame(maxWidth: 300, alignment: .leading)
                    
                    Text(
                        unitPresentation.paceText(
                            fromMinutesPerKilometer: totals.averagePace
                        )
                    )
                        .frame(maxWidth: 300, alignment: .leading)
                        .padding(.top, 3)
                    Text("average pace")
                        .frame(maxWidth: 300, alignment: .leading)
                    
                }.font(Font.custom("CallingCode-Regular", size: 18))
                    .padding(.top, 30)
                
            }
            .foregroundStyle(selectedDay == nil ? Color.white : Color.flashHighlight)
            .animation(.easeOut(duration: 0.15), value: selectedDay)
            .padding(.bottom, 100)
        
    }
}
