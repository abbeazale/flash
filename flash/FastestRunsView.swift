// RunListPage.swift
import SwiftUI

struct RunListPage: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let runs: [RunningData]
    let metric: (RunningData) -> String

    var body: some View {
        List(runs) { run in
            NavigationLink(value: run) {
                HStack {
                    Text(run.date.formatted(.dateTime.day().month().weekday()))
                        .font(.custom("CallingCode-Regular", size: 16))
                    Spacer()
                    Text(metric(run))
                        .font(.custom("CallingCode-Regular", size: 16))
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
