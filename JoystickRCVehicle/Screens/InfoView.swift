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
                Section(header: Text("Control Information").font(.largeTitle).bold()) {
                    EmptyView() // Başlık için boş bir görünüm
                }
                
                // Joystick Info
                Section(header: Text("Joysticks")) {
                    VStack(alignment: .leading) {
                        Text("• Left Joystick:")
                            .font(.headline)
                        Text("  - Controls movement (forward, backward, left, right).")
                        Text("  - Returns values between 0 and 99 for X and Y coordinates.")
                        
                        Text("• Right Joystick:")
                            .font(.headline)
                        Text("  - Controls turret rotation (left, right, up, down).")
                        Text("  - Returns values between 0 and 99 for X and Y coordinates.")
                    }
                }
                
                // Button Info
                Section(header: Text("Buttons")) {
                    VStack(alignment: .leading) {
                        Text("• Laser Button:")
                            .font(.headline)
                        Text("  - Toggles laser on and off.")
                        Text("  - Returns 'L' for ON and 'l' for OFF.")
                        
                        Text("• Fire Button:")
                            .font(.headline)
                        Text("  - Activates the fire mechanism.")
                        Text("  - Returns 'F' for pressed and 'f' for released.")
                        
                        Text("• Trigger Button:")
                            .font(.headline)
                        Text("  - Works in combination with the Fire button for precise control.")
                        Text("  - Returns 'T' for pressed and 't' for released.")
                    }
                }
                
                // Gyro Info
                Section(header: Text("Gyro Control")) {
                    VStack(alignment: .leading) {
                        Text("• Gyro Control:")
                            .font(.headline)
                        Text("  - Enables device motion-based control.")
                        Text("  - Updates the right joystick values based on rotation rate.")
                    }
                }
                
                // Bluetooth Info
                Section(header: Text("Bluetooth Connection")) {
                    VStack(alignment: .leading) {
                        Text("• Bluetooth Connection:")
                            .font(.headline)
                        Text("  - Connects to the tank for remote control.")
                        Text("  - Status: 'Connected' or 'Disconnected'.")
                    }
                }
            }
            .listStyle(InsetGroupedListStyle()) // iOS 14+ için modern liste stili
            .navigationTitle("Info")
        }
    }
}
