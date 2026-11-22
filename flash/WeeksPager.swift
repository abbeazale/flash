//
//  WeeksPager.swift
//  flash
//

import SwiftUI

/// Home-screen weekly summary. Swipe right, or tap the left arrow, to see older weeks.
struct WeeksPager: View {
    @EnvironmentObject var manager: HealthManager
    /// Weeks before the current week. 0 is this week.
    @State private var weeksAgo: Int? = 0
    @State private var pastWeeks: [Date: WeekSummary] = [:]
    /// The day picked on the visible week's chart. 0 is Monday. nil shows the whole week.
    @State private var selectedDay: Int?

    /// This week plus every week back to the week of the oldest run.
    private var weekCount: Int {
        guard let firstRunWeekStart = manager.firstRunWeekStart else { return 1 }
        return WeekSummary.weeksBetween(firstRunWeekStart, and: manager.thisWeek.weekStart) + 1
    }

    var body: some View {
        let count = weekCount

        VStack(spacing: 0) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    // Oldest week on the left, this week on the right.
                    ForEach((0..<count).reversed(), id: \.self) { ago in
                        page(weeksAgo: ago)
                            .containerRelativeFrame(.horizontal)
                            .id(ago)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $weeksAgo)
            .defaultScrollAnchor(.trailing)
            // Take the page's height, not all free space, so the home layout stays centered.
            .fixedSize(horizontal: false, vertical: true)
            // Rebuild when the week count arrives so the pager opens on this week.
            .id(count)
            .onChange(of: count) { weeksAgo = 0 }
            // A selection belongs to one week, so drop it when the week changes.
            .onChange(of: weeksAgo) { selectedDay = nil }

            navigation(count: count)
        }
    }

    private func weekStart(weeksAgo ago: Int) -> Date {
        let calendar = Calendar.mondayFirst
        let thisWeekStart = manager.thisWeek.weekStart
        return calendar.date(byAdding: .day, value: -7 * ago, to: thisWeekStart)?
            .startOfWeek(using: calendar) ?? thisWeekStart
    }

    @ViewBuilder
    private func page(weeksAgo ago: Int) -> some View {
        let start = weekStart(weeksAgo: ago)
        let loaded = ago == 0 ? manager.thisWeek : pastWeeks[start]
        let summary = loaded ?? .empty(weekStart: start)

        let isVisible = ago == (weeksAgo ?? 0)
        let daySelection = Binding<Int?>(
            get: { isVisible ? selectedDay : nil },
            set: { if isVisible { selectedDay = $0 } }
        )

        VStack(spacing: 0) {
            WeeklySummery(summary: summary, selectedDay: daySelection.wrappedValue)
            ChartsView(summary: summary, selectedDay: daySelection)
        }
        .opacity(loaded == nil ? 0.4 : 1)
        .task(id: start) {
            guard ago != 0, pastWeeks[start] == nil else { return }
            pastWeeks[start] = await manager.weekSummary(for: start)
        }
    }

    private func navigation(count: Int) -> some View {
        let current = weeksAgo ?? 0
        let start = weekStart(weeksAgo: current)
        let end = Calendar.mondayFirst.date(byAdding: .day, value: 6, to: start) ?? start
        let dayFormat = Date.FormatStyle().month(.abbreviated).day()

        return HStack {
            Button {
                move(to: current + 1)
            } label: {
                Image(systemName: "chevron.left")
                    .padding(8)
            }
            .disabled(current + 1 >= count)
            .opacity(current + 1 >= count ? 0.3 : 1)
            .accessibilityLabel("Previous week")

            Spacer()

            Button {
                move(to: 0)
            } label: {
                Text("\(start.formatted(dayFormat)) – \(end.formatted(dayFormat))")
                    .textCase(.lowercase)
            }
            .buttonStyle(.plain)
            .accessibilityHint(current == 0 ? "" : "Goes back to this week")

            Spacer()

            Button {
                move(to: current - 1)
            } label: {
                Image(systemName: "chevron.right")
                    .padding(8)
            }
            .disabled(current == 0)
            .opacity(current == 0 ? 0.3 : 1)
            .accessibilityLabel("Next week")
        }
        .frame(maxWidth: 300)
        .tint(.white)
    }

    private func move(to ago: Int) {
        withAnimation {
            weeksAgo = ago
        }
    }
}
