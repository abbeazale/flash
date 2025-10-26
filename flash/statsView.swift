//
//  statsView.swift
//  flash
//
//  Created by abbe on 2024-05-30.
//
import SwiftUI

//stats of run
struct statsView: View {
    let workout: RunningData
    @State private var cachedElevationSegments: [Double] = []
    
    var body: some View {
        ScrollView {
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
            .frame(maxWidth: .infinity)
            
            // REDESIGNED ELEVATION SECTION
            VStack(alignment: .leading, spacing: 12){
                HStack(alignment: .firstTextBaseline) {
                    Text("Elevation")
                        .font(Font.custom("CallingCode-Regular", size: 24))
                    
                    Spacer()
                    
                    if let max = cachedElevationSegments.max(),
                       let min = cachedElevationSegments.min() {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(max))m")
                                .font(Font.custom("CallingCode-Regular", size: 14))
                                .foregroundColor(.green)
                            Text("\(Int(min))m")
                                .font(Font.custom("CallingCode-Regular", size: 14))
                                .foregroundColor(.green.opacity(0.6))
                        }
                    }
                }
                .padding(.horizontal)
                
                // Elevation Chart
                GeometryReader { geometry in
                    ZStack(alignment: .bottom) {
                        // Background grid
                        VStack(spacing: 0) {
                            ForEach(0..<5) { i in
                                Divider()
                                    .background(Color.white.opacity(0.1))
                                Spacer()
                            }
                        }
                        
                        // Elevation bars
                        HStack(alignment: .bottom, spacing: 1) {
                            ForEach(Array(cachedElevationSegments.enumerated()), id: \.offset) { index, elevation in
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.green.opacity(0.8),
                                                Color.green.opacity(0.4)
                                            ]),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(
                                        width: max(2, (geometry.size.width - CGFloat(cachedElevationSegments.count)) / CGFloat(cachedElevationSegments.count)),
                                        height: max(5, elevationHeight(elevation, maxHeight: geometry.size.height))
                                    )
                                    .cornerRadius(1)
                            }
                        }
                    }
                }
                .frame(height: 180)
                .padding(.horizontal)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.05))
                )
                .padding(.horizontal)
                
                // Time labels
                HStack {
                    Text("0:00")
                        .font(Font.custom("CallingCode-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Spacer()
                    
                    Text(workout.formattedDuration)
                        .font(Font.custom("CallingCode-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.horizontal, 24)
                
                // Total elevation gain
                if workout.elevation > 0 {
                    HStack {
                        Image(systemName: "arrow.up.right")
                            .foregroundColor(.green)
                        Text("Total Elevation Gain: \(Int(workout.elevation))m")
                            .font(Font.custom("CallingCode-Regular", size: 16))
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }
            .padding(.vertical)
            .frame(maxWidth: .infinity)
        }
        .background(Color(red: 54 / 255, green: 46 / 255, blue: 64/255))
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            // Cache elevation segments once on appear
            cachedElevationSegments = elevationSegments()
        }
    }
}

extension statsView{
    private func barWidth(for pace: Double) -> CGFloat {
        let maxPace = workout.pacePerKM.map { $0.pace }.max() ?? 1
        let maxWidth: CGFloat = 200 // Fixed width for bars
        
        return CGFloat((pace / maxPace) * Double(maxWidth))
    }

    
    private func elevationSegments() -> [Double] {
        guard !workout.route.isEmpty else { return [] }
        
        let segmentCount = 60
        let segmentLength = max(1, workout.route.count / segmentCount)
        var segments: [Double] = []
        
        for i in stride(from: 0, to: workout.route.count, by: segmentLength) {
            let endIndex = min(i + segmentLength, workout.route.count)
            let segment = workout.route[i..<endIndex]
            let avgElevation = segment.map { $0.altitude }.average()
            segments.append(avgElevation)
        }
        
        return segments
    }
    
    private func elevationHeight(_ elevation: Double, maxHeight: CGFloat) -> CGFloat {
        guard !cachedElevationSegments.isEmpty else { return 5 }
        
        let maxElevation = cachedElevationSegments.max() ?? 1.0
        let minElevation = cachedElevationSegments.min() ?? 0.0
        let range = maxElevation - minElevation
        
        // Avoid division by zero for flat terrain
        guard range > 0 else { return maxHeight * 0.5 }
        
        let normalizedElevation = (elevation - minElevation) / range
        return CGFloat(normalizedElevation * Double(maxHeight * 0.9)) // Use 90% of height for better visibility
    }
}

// Helper to calculate the average of an array of Doubles
extension Array where Element == Double {
    func average() -> Double {
        return self.isEmpty ? 0 : self.reduce(0, +) / Double(self.count)
    }
}
