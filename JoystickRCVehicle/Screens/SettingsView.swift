//
//  SettingsView.swift
//  JoystickRCVehicle
//
//  Created by Onder Guler on 6.12.2024.
//


import SwiftUI

struct SettingsView: View {
    @AppStorage("isHapticFeedbackEnabled") private var isHapticFeedbackEnabled: Bool = true
    @AppStorage("selectedTheme") private var selectedTheme: String = "System"

    @State private var controlSensitivity: Double = 50
    @State private var isBluetoothEnabled: Bool = true
    
    var body: some View {
        NavigationView {
            List {
                // Bluetooth Settings
                Section(header: Text("Bluetooth")) {
                    Toggle("Enable Bluetooth", isOn: $isBluetoothEnabled)
                        .onChange(of: isBluetoothEnabled) { newValue in
                            // Handle Bluetooth enable/disable action here
                        }
                }
                
                // Control Sensitivity
                Section(header: Text("Control Settings")) {
                    VStack(alignment: .leading) {
                        Text("Control Sensitivity")
                        Slider(value: $controlSensitivity, in: 1...100, step: 1)
                        Text("Current Sensitivity: \(Int(controlSensitivity))")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Toggle("Enable Haptic Feedback", isOn: $isHapticFeedbackEnabled)
                }
                
                // Theme Settings
                Section(header: Text("Appearance")) {
                    Picker("Select Theme", selection: $selectedTheme) {
                        Text("Light").tag("Light")
                        Text("Dark").tag("Dark")
                        Text("System Default").tag("System")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                // About Section
                Section(header: Text("About")) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Rc Car JoystickMaster")
                            .font(.headline)
                        Text("Version: \(Bundle.main.appVersion).\(Bundle.main.buildNumber)")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Text("Developed by Onder Guler")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Settings")
            .preferredColorScheme(getColorScheme())
        }
        
    }
    private func getColorScheme() -> ColorScheme? {
            switch selectedTheme {
            case "Light":
                return .light
            case "Dark":
                return .dark
            default:
                return nil // System default
            }
        }
}
