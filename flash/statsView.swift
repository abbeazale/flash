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
        VStack(alignment: .leading) {
            Text("Splits")
                .font(.system(size: 24, weight: .bold))
                .padding(.bottom, 16)
            
            HStack {
                Text("Km")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Text("Pace")
                    .font(.system(size: 18, weight: .bold))
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            
            //convert pace to MM:Ss
            ForEach(workout.pacePerKM, id: \.kilometer) { segment in
                HStack {
                    Text("\(segment.kilometer)")
                        .font(.system(size: 18))
                        .frame(width: 30, alignment: .leading)
                    Spacer()
                    Text(segment.formattedPace)
                        .font(.system(size: 18))
                        .frame(width: 50, alignment: .trailing)
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: self.barWidth(for: segment.pace), height: 20)
                        .cornerRadius(4)
                }
                .padding(.horizontal)
            }
        }
        .padding()
        .frame(width: 300, alignment: .center)
    }
    
    private func barWidth(for pace: Double) -> CGFloat {
        let maxPace = workout.pacePerKM.map { $0.pace }.max() ?? 1
        let maxWidth: CGFloat = 200 // Fixed width for bars
        
        return CGFloat((pace / maxPace) * Double(maxWidth))
    }
}
