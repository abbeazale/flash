//
//  statsView.swift
//  flash
//
//  Created by abbe on 2024-05-30.
//
import SwiftUI
import Charts

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
            
            // HEART RATE SECTION
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Heart Rate")
                        .font(Font.custom("CallingCode-Regular", size: 24))
                    
                    Spacer()
                    
                    if let maxHR = workout.heartRateData.map({ $0.heartRate }).max(),
                       let minHR = workout.heartRateData.map({ $0.heartRate }).min() {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(maxHR)) bpm")
                                .font(Font.custom("CallingCode-Regular", size: 14))
                                .foregroundColor(.red)
                            Text("Avg: \(Int(workout.heartRate)) bpm")
                                .font(Font.custom("CallingCode-Regular", size: 14))
                                .foregroundColor(.orange)
                            Text("\(Int(minHR)) bpm")
                                .font(Font.custom("CallingCode-Regular", size: 14))
                                .foregroundColor(.red.opacity(0.6))
                        }
                    }
                }
                .padding(.horizontal)
                
                // Heart Rate Chart
                if !workout.heartRateData.isEmpty {
                    GeometryReader { geometry in
                        Chart {
                            ForEach(Array(workout.heartRateData.enumerated()), id: \.offset) { index, dataPoint in
                                LineMark(
                                    x: .value("Time", dataPoint.relativeTime),
                                    y: .value("Heart Rate", dataPoint.heartRate)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.red, .orange]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .lineStyle(StrokeStyle(lineWidth: 2))
                                
                                AreaMark(
                                    x: .value("Time", dataPoint.relativeTime),
                                    y: .value("Heart Rate", dataPoint.heartRate)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.red.opacity(0.3),
                                            Color.orange.opacity(0.1)
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            }
                        }
                        .chartXAxis {
                            AxisMarks(position: .bottom) { _ in
                                AxisGridLine().foregroundStyle(Color.white.opacity(0.1))
                                AxisTick().foregroundStyle(.clear)
                                AxisValueLabel()
                                    .foregroundStyle(.white.opacity(0.6))
                                    .font(Font.custom("CallingCode-Regular", size: 12))
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { _ in
                                AxisGridLine().foregroundStyle(Color.white.opacity(0.1))
                                AxisValueLabel()
                                    .foregroundStyle(.white.opacity(0.6))
                                    .font(Font.custom("CallingCode-Regular", size: 12))
                            }
                        }
                        .chartXScale(domain: 0...(workout.duration))
                    }
                    .frame(height: 200)
                    .padding(.horizontal)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.05))
                    )
                    .padding(.horizontal)
                } else {
                    Text("No heart rate data available")
                        .font(Font.custom("CallingCode-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal)
                }
                
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
            }
            .padding(.vertical)
            .frame(maxWidth: .infinity)
            
            // HEART RATE ZONES SECTION
            VStack(alignment: .leading, spacing: 12) {
                Text("Heart Rate Zones")
                    .font(Font.custom("CallingCode-Regular", size: 24))
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                
                if !workout.heartRateZones.isEmpty {
                    ForEach(workout.heartRateZones) { zone in
                        HStack {
                            // Zone name and range
                            VStack(alignment: .leading, spacing: 4) {
                                Text(zone.zone)
                                    .font(Font.custom("CallingCode-Regular", size: 16))
                                    .foregroundColor(.white)
                                Text(zone.range)
                                    .font(Font.custom("CallingCode-Regular", size: 12))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            .frame(width: 100, alignment: .leading)
                            
                            // Percentage bar
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(height: 30)
                                    .cornerRadius(6)
                                
                                Rectangle()
                                    .fill(Color(hex: zone.color))
                                    .frame(width: max(30, CGFloat(zone.percentage) * 1.8), height: 30)
                                    .cornerRadius(6)
                            }
                            
                            // Percentage text
                            Text(String(format: "%.1f%%", zone.percentage))
                                .font(Font.custom("CallingCode-Regular", size: 16))
                                .foregroundColor(.white)
                                .frame(width: 60, alignment: .trailing)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
                } else {
                    Text("No heart rate zone data available")
                        .font(Font.custom("CallingCode-Regular", size: 14))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal)
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

// Extension to create Color from hex string
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
