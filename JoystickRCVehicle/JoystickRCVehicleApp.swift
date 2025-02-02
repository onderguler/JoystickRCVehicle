//
//  JoystickRCVehicleApp.swift
//  JoystickRCVehicle
//
//  Created by Onder Guler on 24.09.2024.
//

import SwiftUI

@main
struct JoystickRCVehicleApp: App {
    @AppStorage("selectedTheme") private var selectedTheme: String?
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(getColorScheme())
        }
    }
    // Function to determine the appropriate ColorScheme
    private func getColorScheme() -> ColorScheme? {
        switch selectedTheme {
        case "Light":
            return .light
        case "Dark":
            return .dark
        default:
            return nil
        }
    }
}
