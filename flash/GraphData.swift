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
/// Tap a bar, or press and drag across the bars, to select a day.
struct ChartsView: View {
    let summary: WeekSummary
    /// The selected day. 0 is Monday. nil shows the whole week.
    @Binding var selectedDay: Int?
    @Query private var profiles: [RunnerProfile]

    private var unitPresentation: RunUnitPresentation {
        RunUnitPresentation(
            unit: profiles.first { $0.key == RunnerProfile.singletonKey }?.distanceUnit
                ?? .kilometers
        )
    }

    var body: some View {
        let days = summary.days()
        let labels = days.map { $0.startOfWeekFormatted() }
        let selectedLabel = selectedDay.flatMap { labels.indices.contains($0) ? labels[$0] : nil }

        Chart {
            ForEach(days.indices, id: \.self) { index in
                BarMark(
                    x: .value("Day", labels[index]),
                    y: .value(
                        "\(unitPresentation.unit.title) Ran",
                        unitPresentation.distance(fromMeters: summary.dailyKilometers[index] * 1_000)
                    )
                )
                .foregroundStyle(barColor(for: index))
            }
        }
        .frame(width: 350, height: 300, alignment: .top)
        .padding(.bottom)
        //remove lines from the graph
        .chartXAxis {
            AxisMarks(position: .bottom) { value in
                AxisGridLine().foregroundStyle(.clear)
                AxisTick().foregroundStyle(.clear)
                AxisValueLabel()
                    .foregroundStyle(
                        value.as(String.self) == selectedLabel && selectedLabel != nil
                            ? Color.flashHighlight
                            : Color.white.opacity(0.6)
                    )
            }}
        .chartYAxis(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        scrubGesture(proxy: proxy, geometry: geometry)
                            .exclusively(before: tapGesture(proxy: proxy, geometry: geometry))
                    )
            }
        }
        .animation(.easeOut(duration: 0.15), value: selectedDay)
        .sensoryFeedback(.selection, trigger: selectedDay)
    }

    private func barColor(for index: Int) -> Color {
        guard let selectedDay else { return .white }
        return index == selectedDay ? .flashHighlight : .white.opacity(0.3)
    }

    /// Tap a bar to select it. Tap it again to show the whole week.
    private func tapGesture(proxy: ChartProxy, geometry: GeometryProxy) -> some Gesture {
        SpatialTapGesture().onEnded { value in
            guard let day = day(at: value.location, proxy: proxy, geometry: geometry) else { return }
            selectedDay = selectedDay == day ? nil : day
        }
    }

    /// Press and hold, then drag across the bars to move the selection.
    /// The hold lets a quick swipe still page between weeks.
    private func scrubGesture(proxy: ChartProxy, geometry: GeometryProxy) -> some Gesture {
        LongPressGesture(minimumDuration: 0.2)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case .second(true, let drag?) = value,
                      let day = day(at: drag.location, proxy: proxy, geometry: geometry)
                else { return }
                selectedDay = day
            }
    }

    /// The day under a point in the overlay. The 7 bars split the plot width evenly.
    private func day(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> Int? {
        guard let plotAnchor = proxy.plotFrame else { return nil }
        let plot = geometry[plotAnchor]
        guard plot.width > 0 else { return nil }
        let index = Int((location.x - plot.minX) / (plot.width / 7))
        return min(max(index, 0), 6)
    }
}

extension Date {
    func startOfWeekFormatted() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E" // "E" gives the short form of the day of the week
        return formatter.string(from: self)
    }
}
