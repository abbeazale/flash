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
    @StateObject private var manager = HealthManager()

    init() {
        FirebaseApp.configure()
        configureSentry()
        configureNavigationBarAppearance()
    }

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

private func configureSentry() {
    SentrySDK.start { options in
        options.dsn = "https://1771a11ab0ea1713ed68de28bc64d8ef@o4507802739539968.ingest.us.sentry.io/4507802740916224"

        #if DEBUG
        options.debug = true
        options.tracesSampleRate = 1.0
        #else
        options.debug = false
        options.tracesSampleRate = 0.1
        #endif
    }
}

private func configureNavigationBarAppearance() {
    let appearance = UINavigationBarAppearance()
    appearance.configureWithTransparentBackground()
    appearance.backgroundColor = UIColor(red: 54 / 255, green: 46 / 255, blue: 64 / 255, alpha: 1)
    appearance.shadowColor = .clear

    UINavigationBar.appearance().standardAppearance = appearance
    UINavigationBar.appearance().scrollEdgeAppearance = appearance
}
