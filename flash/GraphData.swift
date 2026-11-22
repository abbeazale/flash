//
//  GraphData.swift
//  flash
//
//  Created by abbe on 2024-04-11.
//

import Foundation
import Charts
import SwiftData
import SwiftUI

/// Bar chart of the distance ran on each day of one Monday-to-Sunday week.
struct ChartsView: View {
    let summary: WeekSummary
    @Query private var profiles: [RunnerProfile]

    private var unitPresentation: RunUnitPresentation {
        RunUnitPresentation(
            unit: profiles.first { $0.key == RunnerProfile.singletonKey }?.distanceUnit
                ?? .kilometers
        )
    }

    var body: some View {
        Chart {
            let days = summary.days()
            ForEach(days.indices, id: \.self) { index in
                BarMark(
                    x: .value("Day", days[index].startOfWeekFormatted()),
                    y: .value(
                        "\(unitPresentation.unit.title) Ran",
                        unitPresentation.distance(fromMeters: summary.dailyKilometers[index] * 1_000)
                    )
                )
            }
        }
        .frame(width: 350, height: 300, alignment: .top)
        .padding(.bottom)
        //remove lines from the graph
        .chartXAxis {
            AxisMarks(position: .bottom) { _ in
                AxisGridLine().foregroundStyle(.clear)
                AxisTick().foregroundStyle(.clear)
                AxisValueLabel()
            }}
        .chartYAxis(.hidden)
    }
}

extension Date {
    func startOfWeekFormatted() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E" // "E" gives the short form of the day of the week
        return formatter.string(from: self)
    }
}
