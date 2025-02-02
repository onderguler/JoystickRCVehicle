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
                Section(header: Text("bluetooth".localized)) {
                    Toggle("enable_bluetooth".localized, isOn: $isBluetoothEnabled)
                        .onChange(of: isBluetoothEnabled) { newValue in
                            // Handle Bluetooth enable/disable action here
                        }
                }
                
                // Control Sensitivity
                Section(header: Text("control_settings".localized)) {
                    VStack(alignment: .leading) {
                        Text("control_sensitivity".localized)
                        Slider(value: $controlSensitivity, in: 1...100, step: 1)
                        Text(String(format: "current_sensitivity".localized, Int(controlSensitivity)))
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Toggle("enable_haptic_feedback".localized, isOn: $isHapticFeedbackEnabled)
                }
                
                // Theme Settings
                Section(header: Text("appearance".localized)) {
                    Picker("select_theme".localized, selection: $selectedTheme) {
                        Text("theme_light".localized).tag("Light")
                        Text("theme_dark".localized).tag("Dark")
                        Text("theme_system_default".localized).tag("System")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                // About Section
                Section(header: Text("about".localized)) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("app_name".localized)
                            .font(.headline)
                        Text(String(format: "app_version".localized, "\(Bundle.main.appVersion).\(Bundle.main.buildNumber)"))
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Text("developed_by".localized)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("settings".localized)
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
