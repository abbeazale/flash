//
//  GraphData.swift
//  flash
//
//  Created by abbe on 2024-04-11.
//

import Foundation
import SwiftUI
import Charts

//data for the graph on the home page
//day will be from apple health
//kmRan will be how much km they ran that day (info from google health)
//maxKM will be the max km ran that day (45km)
struct WeeklyRunData: Identifiable {
    let id = UUID()
    let date: Date
    let kmRan: Double

}

struct ChartsView: View {
    @EnvironmentObject var manager: HealthManager
    
    var body: some View {
        VStack {
            Chart {
                // Generate a full week of dates starting from Monday
                let fullWeek = generateFullWeek()
                
                ForEach(fullWeek, id: \.self) { date in
                    let dailyData = manager.weeklyRunSummery.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
                    BarMark(
                        x: .value("Day", date.startOfWeekFormatted()),
                        y: .value("Kilometers Ran", dailyData?.kmRan ?? 0)
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
            
            let dates = Date().startOfWeek().formatted(Date.FormatStyle()
                .month(.wide)
                .day(.defaultDigits))
            
            Text("week of \(dates)")
                .textCase(.lowercase)
        }
    }
    
    // Generate a full week of dates starting from Monday
        func generateFullWeek() -> [Date] {
            let calendar = Calendar.current
            let startOfWeek = Date().startOfWeek()
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfWeek) }
        }
}

extension Date {
    func startOfWeek() -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return calendar.date(from: components)!
    }
    
    func startOfWeekFormatted() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E" // "E" gives the short form of the day of the week
        return formatter.string(from: self)
    }
}

#Preview {
    ChartsView()
        .environmentObject(HealthManager())
}
