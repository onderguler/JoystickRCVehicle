//
//  ContentView.swift
//  JoystickRCVehicle
//
//  Created by Onder Guler on 24.09.2024.
//

import SwiftUI
import CoreMotion

struct ContentView: View {
    @State private var showingBluetoothDevices = false
    @State private var showingInfoView = false
    @State private var showToast = false
    @State private var showMessage = "Connect to Bluetooth Device First"
    

    @State private var combinedData = ""
    var bluetoothManager = BluetoothManager()
    
    // Sol ve sağ joystick verilerini saklayan state
    @State private var leftJoystickValue = "0,0"  // Sol joystick
    @State private var rightJoystickValue = "0,0" // Sağ joystick
    @State private var laserButtonValue = "l" // Laser buton verisi
    @State private var fireButtonValue = "f" // Fire buton verisi
    @State private var triggerButtonValue = "t" // Trigger buton verisi
    private let motionManager = CMMotionManager()
    @State private var isControlling: Bool = false
    @State private var accumulatedX: Double = 0.0
    @State private var accumulatedY: Double = 0.0
    
    func toggleGyroUpdates() {
        if isControlling {
            stopGyroUpdates()
        } else {
            startGyroUpdates()
        }
        isControlling.toggle()
    }
    
    private func startGyroUpdates() {
        if motionManager.isGyroAvailable {
            motionManager.gyroUpdateInterval = 0.1
            motionManager.startGyroUpdates(to: OperationQueue.main) { data, error in
                guard let gyroData = data else { return }
                
                // Rotation rate'i biriktirerek kullanıyoruz
                let rotationRateX = gyroData.rotationRate.x * 100.0
                let rotationRateY = gyroData.rotationRate.y * 100.0
                
                // Yeni pozisyonları önceki pozisyonlara ekleyerek biriktiriyoruz
                accumulatedX += rotationRateX * 0.1 // Kümülatif birikim
                accumulatedY += rotationRateY * 0.1 // Kümülatif birikim
                
                // Yeni değerleri sınırlandır
                let xValue = constrain(Int(accumulatedX), min: -100, max: 100)
                let yValue = constrain(Int(accumulatedY), min: -100, max: 100)
                
                // Joystick verilerini güncelle
                rightJoystickValue = "\(xValue),\(yValue)"
                updateAndSendCombinedJoystickData()
            }
        }
    }
    
    private func stopGyroUpdates() {
        motionManager.stopGyroUpdates()
        
        accumulatedX = 0.0
        accumulatedY = 0.0
        rightJoystickValue = "\(accumulatedX),\(accumulatedY)"
        updateAndSendCombinedJoystickData()
    }
    
    var body: some View {
        VStack {
            VStack {
                HStack {
                    Button(action: {
                        showingInfoView = true
                    }) {
                        Image(systemName: "info.circle")
                            .resizable()
                            .frame(width: 40, height: 40)
                            .padding()
                            .background(Color.blue)
                            .clipShape(Circle())
                            .foregroundColor(.white)
                    }
                    .sheet(isPresented: $showingInfoView) {
                        InfoView()
                    }

                    Spacer()
                    Button(action: {
                        showingBluetoothDevices = true  // Bluetooth cihaz listesini açar
                    }) {
                        Image(systemName: bluetoothManager.isConnected ?  "cable.connector" : "cable.connector.slash")
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
                    // Gyro Kontrol Butonu
                    Button(action: {
                        if bluetoothManager.isConnected {
                            toggleGyroUpdates()
                        } else {
                            showToast = true
                        }
                    }) {
                        Text("Gyro")
                            .font(.title)
                            .padding()
                            .background(isControlling ? Color.red : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
            }
            .padding(20)
            Spacer()
            Text("\(combinedData)")
            
            HStack {
                // Sol joystick
                JoystickView(size: 250, joyStickOnChange: { translation in
                    leftJoystickValue = translation
                    updateAndSendCombinedJoystickData()
                }, type: .movement)
                
                Spacer()
                ZStack {
                       JoystickView(size: 250, joyStickOnChange: { translation in
                           rightJoystickValue = translation
                           updateAndSendCombinedJoystickData()
                       }, type: .turret)
                       
                       // Fire Button
                       Button(action: {
                           if bluetoothManager.isConnected {
                               if fireButtonValue == "F" {
                                   fireButtonValue = "f"
                                   triggerButtonValue = "t"
                               } else {
                                   fireButtonValue = "F"
                               }
                               updateAndSendCombinedJoystickData()
                           } else {
                               showToast = true
                           }
                       }) {
                           Image(systemName: "bolt.fill") // Uygun ikon
                               .resizable()
                               .frame(width: 40, height: 40)
                               .padding()
                               .background(fireButtonValue == "F" ? Color.red : Color.blue)
                               .clipShape(Circle())
                               .foregroundColor(.white)
                       }
                       .offset(x: -148, y: -80) // Sağ joystick'in sol üst köşesi için yerleşim
                       
                       // Trigger Button
                       Button(action: {
                           if bluetoothManager.isConnected {
                               if triggerButtonValue == "T" {
                                   triggerButtonValue = "t"
                               } else if fireButtonValue == "F" && triggerButtonValue == "t" {
                                   triggerButtonValue = "T"
                               } else {
                                   showMessage = "Enable the fire button first"
                                   showToast = true
                               }
                               updateAndSendCombinedJoystickData()
                           } else {
                               showToast = true
                           }
                       }) {
                           Image(systemName: "flame.fill") // Uygun ikon
                               .resizable()
                               .frame(width: 40, height: 40)
                               .padding()
                               .background(triggerButtonValue == "T" ? Color.red : Color.blue)
                               .clipShape(Circle())
                               .foregroundColor(.white)
                       }
                       .offset(x: -168, y: 0) // Sağ joystick'in sol üst köşesi için yerleşim
                    // Laser Button
                    Button(action: {
                        if bluetoothManager.isConnected {
                            laserButtonValue = (laserButtonValue == "L") ? "l" : "L"
                            updateAndSendCombinedJoystickData()
                        } else {
                            showToast = true
                        }
                        
                    }) {
                        Image(systemName: "target") // Uygun ikon
                            .resizable()
                            .frame(width: 40, height: 40)
                            .padding()
                            .background(laserButtonValue == "L" ? Color.red : Color.blue)
                            .clipShape(Circle())
                            .foregroundColor(.white)
                    }
                    .offset(x: -148, y: 80)
                }
            }
        }
        .padding(.horizontal)
        .toast(isPresented: $showToast, message: showMessage)
    }
    
    // Joystick verilerini birleştirip Bluetooth'a gönderir
    func updateAndSendCombinedJoystickData() {
        combinedData = "\(leftJoystickValue);\(rightJoystickValue);\(laserButtonValue)\(fireButtonValue)\(triggerButtonValue)"
        bluetoothManager.updateJoystickValue(value: combinedData)
        debugPrint(combinedData)
    }
    
    // Gelen değerlerin sınırlandırılması
    private func constrain(_ value: Int, min: Int, max: Int) -> Int {
        return Swift.min(Swift.max(value, min), max)
    }
}
