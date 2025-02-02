//
//  InfoView.swift
//  JoystickRCVehicle
//
//  Created by Onder Guler on 6.12.2024.
//

import SwiftUI
struct InfoView: View {
    var body: some View {
        NavigationView {
            List {
                // Control Information Title
                Section(header: Text("control_information".localized).font(.largeTitle).bold()) {
                    EmptyView()
                }

                // Joystick Info
                Section(header: Text("joysticks".localized)) {
                    VStack(alignment: .leading) {
                        Text("left_joystick".localized).font(.headline)
                        Text("left_joystick_desc1".localized)
                        Text("left_joystick_desc2".localized)
                        
                        Text("right_joystick".localized).font(.headline)
                        Text("right_joystick_desc1".localized)
                        Text("right_joystick_desc2".localized)
                    }
                }

                // Button Info
                Section(header: Text("buttons".localized)) {
                    VStack(alignment: .leading) {
                        Text("laser_button".localized).font(.headline)
                        Text("laser_button_desc1".localized)
                        Text("laser_button_desc2".localized)
                        
                        Text("fire_button".localized).font(.headline)
                        Text("fire_button_desc1".localized)
                        Text("fire_button_desc2".localized)
                        
                        Text("trigger_button".localized).font(.headline)
                        Text("trigger_button_desc1".localized)
                        Text("trigger_button_desc2".localized)
                    }
                }

                // Gyro Info
                Section(header: Text("gyro_control".localized)) {
                    VStack(alignment: .leading) {
                        Text("gyro_control".localized).font(.headline)
                        Text("gyro_control_desc1".localized)
                        Text("gyro_control_desc2".localized)
                    }
                }

                // Bluetooth Info
                Section(header: Text("bluetooth_connection".localized)) {
                    VStack(alignment: .leading) {
                        Text("bluetooth_connection".localized).font(.headline)
                        Text("bluetooth_connection_desc1".localized)
                        Text("bluetooth_connection_desc2".localized)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("info_title".localized)
        }
    }
}
