//
//  flashApp.swift
//  flash
//
//  Created by abbe on 2024-04-05.
//

import SwiftUI
import FirebaseCore

@main
struct flashApp: App {
    @StateObject var manager = HealthManager()
    
    //initilize firebase
    init() {
            FirebaseApp.configure()
        }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(manager)
                .onAppear {
                    // Start periodic sync when the app appears
                    manager.startPeriodSync()
                }
                
        }
    }
}
