//
//  RunsListView.swift
//  flash
//
//  Created by abbe on 2025-06-23.
//

import SwiftUI

struct RunListPage: View {
    let title: String
    let runs: [RunningData]
    let metric: (RunningData) -> String

    var body: some View {
        ZStack {
            Color.flashBackground
                .ignoresSafeArea()

            if runs.isEmpty {
                Text("No runs yet")
                    .font(Font.custom("CallingCode-Regular", size: 16))
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                ScrollView(.vertical) {
                    LazyVStack {
                        ForEach(runs) { run in
                            NavigationLink(destination: DetailedRun(workout: run)) {
                                HStack {
                                    Text(run.date.formatted(.dateTime
                                        .day(.defaultDigits)
                                        .month(.wide)
                                        .weekday(.wide)
                                        .year()))
                                    .font(.headline)
                                    Text(metric(run))
                                        .font(.subheadline)
                                }
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
        .foregroundColor(.white)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.flashBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
