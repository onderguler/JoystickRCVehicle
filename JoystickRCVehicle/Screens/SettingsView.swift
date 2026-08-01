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
    @AppStorage("movementSensitivity") private var movementSensitivity: Double = 50
    @AppStorage("turretSensitivity") private var turretSensitivity: Double = 50

    @Environment(\.presentationMode) private var presentationMode
    
    var body: some View {
        NavigationView {
            List {
                // Control Sensitivity
                Section(header: Text("control_settings".localized)) {
                    sensitivityControl(
                        title: "movement_sensitivity".localized,
                        value: $movementSensitivity,
                        identifier: "movementSensitivitySlider"
                    )
                    sensitivityControl(
                        title: "turret_sensitivity".localized,
                        value: $turretSensitivity,
                        identifier: "turretSensitivitySlider"
                    )
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
            .navigationBarItems(trailing: Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Image(systemName: "xmark")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("settingsCloseButton"))
            .preferredColorScheme(getColorScheme())
        }
    }

    private func sensitivityControl(
        title: String,
        value: Binding<Double>,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue))%")
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: 0...100, step: 1)
                .accessibilityIdentifier(identifier)
        }
        .padding(.vertical, 4)
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
