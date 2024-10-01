//
//  ContentView.swift
//  JoystickRCVehicle
//
//  Created by Onder Guler on 24.09.2024.
//

import SwiftUI

struct ContentView: View {
    @State private var showingBluetoothDevices = false
    var bluetoothManager = BluetoothManager()
    
    // Sol ve sağ joystick verilerini saklayan state
    @State private var leftJoystickValue = "0,0"  // Sol joystick
    @State private var rightJoystickValue = "0,0" // Sağ joystick
    @State private var laserButtonValue = "l" // Sağ joystick
    @State private var fireButtonValue = "f" // Sağ joystick
    @State private var triggerButtonValue = "t" // Sağ joystick

    var body: some View {
        VStack {
            VStack {
                HStack {
                    Button(action: {
                        self.showingBluetoothDevices = true  // Bluetooth cihaz listesini açar
                    }) {
                        Image(systemName:bluetoothManager.isConnected ?  "cable.connector" : "cable.connector.slash")
                            .resizable()
                            .frame(width: 40, height: 40)
                            .padding()
                            .background(bluetoothManager.isConnected ? Color.blue.opacity(0.7): .red.opacity(0.7))
                            .clipShape(Circle())
                            .foregroundColor(.white)
                    }
                    .sheet(isPresented: $showingBluetoothDevices) {
                        // Bluetooth cihaz listesini burada açabilirsiniz
                        BluetoothDeviceListView(bluetoothManager: bluetoothManager)
                    }
                    
                    // Lazer Butonu
                    Button(action: {
                        if self.laserButtonValue == "L" {
                            self.laserButtonValue = "l"
                        } else {
                            self.laserButtonValue = "L"
                        }
                        updateAndSendCombinedJoystickData()
                    }) {
                        Text("Laser")
                            .font(.title)
                            .padding()
                            .background(laserButtonValue == "L" ? Color.red : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    
                    // Ateş Butonu
                    Button(action: {
                        if self.fireButtonValue == "F" {
                            self.fireButtonValue = "f"
                            self.triggerButtonValue = "t"
                        } else {
                            self.fireButtonValue = "F"
                        }
                        updateAndSendCombinedJoystickData()
                        
                    }) {
                        Text("Fire")
                            .font(.title)
                            .padding()
                            .background(fireButtonValue == "F" ? Color.red : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    // Ateş Butonu
                    Button(action: {
                        if self.triggerButtonValue == "T" {
                            self.triggerButtonValue = "t"
                        } else if  fireButtonValue == "F" && triggerButtonValue == "t" {
                            self.triggerButtonValue = "T"
                        }
                        updateAndSendCombinedJoystickData()
                        
                    }) {
                        Text("Trigger")
                            .font(.title)
                            .padding()
                            .background(triggerButtonValue == "T" ? Color.red : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
            }
            .padding(.horizontal, 10)
            
            HStack {
                // Sol joystick
                JoystickView(size: 250, joyStickOnChange: { translation in
                    // Sol joystick verisini güncelle
                    self.leftJoystickValue = translation
                    self.updateAndSendCombinedJoystickData()
                }, type: .movement)
                Spacer()
                // Sağ joystick
                JoystickView(size: 250, joyStickOnChange: { translation in
                    // Sağ joystick verisini güncelle
                    self.rightJoystickValue = translation
                    self.updateAndSendCombinedJoystickData()
                }, type: .turret)
            }
        }.padding()
    }
    
    // Sol ve sağ joystick verilerini birleştirip Bluetooth'a gönderir
    func updateAndSendCombinedJoystickData() {
        
        let combinedData = "\(leftJoystickValue)" + ";" + "\(rightJoystickValue)" + ";" + "\(laserButtonValue)" + "\(fireButtonValue)" + "\(triggerButtonValue)"
        bluetoothManager.updateJoystickValue(value: combinedData)
    }
}
