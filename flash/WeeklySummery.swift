//
//  SwiftUIView.swift
//  flash
//
//  Created by abbe on 2024-04-12.
//

import SwiftUI


struct Stats {
    let id = UUID()
    let totalKm: Double
    let totalTime: String
    let averagePace: Double
    let formattPace: String

}

struct WeeklySummery: View {
    @EnvironmentObject var manager: HealthManager
    @State var stats: Stats

//weekly run summery array of data 

    var body: some View {
            VStack{
               
                Text("\(manager.weeklyRunDistance, specifier: "%.2f")")
                    .font(Font.custom("CallingCode-Regular", size: 96))
                Text("kilometers")
                    .font(Font.custom("CallingCode-Regular", size: 16))
                    .opacity(0.30)
                VStack{
                    Text(String(manager.formattedRunTime))
                        .frame(maxWidth: 300, alignment: .leading)
                    Text("time")
                        .frame(maxWidth: 300, alignment: .leading)
                    
                    Text(String(manager.formattedRunPace))
                        .frame(maxWidth: 300, alignment: .leading)
                        .padding(.top, 3)
                    Text("average pace")
                        .frame(maxWidth: 300, alignment: .leading)
                }.font(Font.custom("CallingCode-Regular", size: 18))
                    .padding(.top, 30)
                
            }.padding(.bottom, 100)
            
        
    }
}

//#Preview {
    //WeeklySummery(stats: Stats(id: 0, totalKm: 52.07, totalTime: 6300.36, averagePace: 300.26))
//}
