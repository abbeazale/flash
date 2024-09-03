//
//  flashApp.swift
//  flash
//
//  Created by abbe on 2024-04-05.
//

import SwiftUI
import Sentry

import FirebaseCore

@main
struct flashApp: App {
    init() {
        FirebaseApp.configure()
        SentrySDK.start { options in
            options.dsn = "https://1771a11ab0ea1713ed68de28bc64d8ef@o4507802739539968.ingest.us.sentry.io/4507802740916224"
            options.debug = true // Enabled debug when first installing is always helpful
           

            // Uncomment the following lines to add more data to your events
            // options.attachScreenshot = true // This adds a screenshot to the error events
            // options.attachViewHierarchy = true // This adds the view hierarchy to the error events
            
            options.tracesSampleRate = 1.0

               
        }
        // Remove the next line after confirming that your Sentry integration is working.
        SentrySDK.capture(message: "This app uses Sentry! :)")
    }
    @StateObject var manager = HealthManager()
    
    //initilize firebase
    //init() {
      //  FirebaseApp.configure()
        //}
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(manager)
                /*.onAppear {
                    // Start periodic sync when the app appears
                    manager.startPeriodSync()
                }
                .onDisappear {
                    // Stop periodic sync when the app disappears
                    manager.stopSync()
            } */
        }
    }
}
