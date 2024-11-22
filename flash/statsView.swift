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
                .font(Font.custom("CallingCode-Regular", size: 24))
                .padding(.bottom, 16)
            HStack {
                Text("Km")
                
                Spacer()
                Text("Pace")
            }
            .font(Font.custom("CallingCode-Regular", size: 18))
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            ForEach(workout.pacePerKM, id: \.kilometer) { segment in
                HStack {
                    Text("\(segment.kilometer)")
                        .font(Font.custom("CallingCode-Regular", size: 18))
                        .frame(width: 20, alignment: .leading)
                       
                    
                    Text(segment.formattedPace)
                        .font(Font.custom("CallingCode-Regular", size: 18))
                        .frame(width: 60, alignment: .leading)
                       
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: self.barWidth(for: segment.pace), height: 20)
                        .cornerRadius(4)
                       
                }
                .padding(.horizontal)
            }
        }
        .padding()
        .frame(width: 350)
        
        Text("Elevation")
            .font(Font.custom("CallingCode-Regular", size: 24))
            .padding(.bottom, 16)
        
        //add start elevation and end elevation
        //add 0:00 to the start and the end time at the end at the bottom
        HStack(alignment: .bottom, spacing: 2){
            ForEach(elevationSegments(), id: \.self) { elevation in
                Rectangle()
                    .fill(Color.green)
                    .frame(width: 4, height: elevationHeight(elevation))
                
            }
        }
        .padding()
        
    }
}

extension statsView{
    private func barWidth(for pace: Double) -> CGFloat {
        let maxPace = workout.pacePerKM.map { $0.pace }.max() ?? 1
        let maxWidth: CGFloat = 200 // Fixed width for bars
        
        return CGFloat((pace / maxPace) * Double(maxWidth))
    }

    
    private func elevationSegments() -> [Double] {
        let segmentCount = 60
        let segmentLength = max(1,workout.route.count / segmentCount)
        var segments: [Double] = []
        
        for i in stride(from: 0, to: workout.route.count, by: segmentLength) {
            let segment = workout.route[i..<min(i+segmentLength, workout.route.count)]
            let avElevation = segment.map {$0.altitude}.average()
            segments.append(avElevation)
            
        }
        print(segments)
        return segments
    }
    
    private func elevationHeight(_ elevation: Double) -> CGFloat {
        let maxElevation = elevationSegments().max() ?? 1.0
        let minElevation = elevationSegments().min() ?? 0.0
        let normalizedElevation = (elevation - minElevation) / (maxElevation - minElevation)
        return CGFloat(normalizedElevation * 150)
    }
}

// Helper to calculate the average of an array of Doubles
extension Array where Element == Double {
    func average() -> Double {
        return self.isEmpty ? 0 : self.reduce(0, +) / Double(self.count)
    }
}
