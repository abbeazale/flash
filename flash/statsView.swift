//
//  statsView.swift
//  flash
//
//  Created by abbe on 2024-05-30.
//
import SwiftUI

struct statsView: View {
    let workout: RunningData

    var body: some View {
        VStack() {
            Text("Splits")
                .font(.system(size: 24, weight: .bold))
                .padding(.top, 16)

            HStack {
                Text("Km")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Text("Pace")
                    .font(.system(size: 18, weight: .bold))
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            ForEach(workout.pacePerKM, id: \.kilometer) { segment in
                HStack {
                    Text("\(segment.kilometer)")
                        .font(.system(size: 18))
                        .frame(width: 30, alignment: .leading)
                    Spacer()
                    Text(segment.formattedPace)
                        .font(.system(size: 18))
                        .frame(width: 50, alignment: .leading)
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: self.barWidth(for: segment.pace) + 10, height: 20)
                        .cornerRadius(4)
                }
                .padding(.horizontal)
            }
        }
        .padding()
    }

    private func barWidth(for pace: Double) -> CGFloat {
        let maxPace = workout.pacePerKM.map { $0.pace }.max() ?? 1
        let minWidth: CGFloat = 20
        let maxWidth: CGFloat = UIScreen.main.bounds.width - 100

        return CGFloat((pace / maxPace) * Double(maxWidth)) + minWidth
    }
}

