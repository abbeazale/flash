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
        VStack{
            Text("advanced details")
                .font(Font.custom("CallingCode-Regular", size: 30))
            
            //graph for the segments
            VStack(alignment: .center){
                //loop over each km in the run
                ForEach(workout.pacePerKM(), id: \.kilometer){ segment in
                    VStack{
                        Text("\(segment.kilometer) km")
                            .font(Font.custom("CallingCode-Regular", size: 20))
                        GeometryReader { geometry in
                            HStack(alignment: .center){
                                Rectangle()
                                    .fill(self.paceColor(segment.pace)) //sets the color fot he bars
                                    .frame(width: self.barWidth(segment.pace, in: geometry.size.width), height: 20)
                                    
                            }
                            Text(segment.formattedPace)
                                .font(Font.custom("CallingCode-Regular", size: 20))
                        }
                    }
                }
            }
            
        }
    }
    
    /// width of each bar based on the pace
    private func barWidth(_ pace: Double, in totalWdith: CGFloat) -> CGFloat{
        //get max pace
        let maxPace = workout.pacePerKM().map{$0.pace}.max() ?? 1
        //print("max pace")
        //print(workout.pacePerKM().map{$0.pace})
        return CGFloat(pace / maxPace) * totalWdith
    
    }
    
    ///color of bar based on pace
    private func paceColor(_ pace: Double ) -> Color{
        //green pace fast
        if pace < 5 {
            return .green
        } else if pace < 5.5 {
            //yellow pace easy
            return .yellow
        } else {
            return .red
        }
    }
}

