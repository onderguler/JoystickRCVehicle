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
                    
                    // Lazer Butonu
                    Button(action: {
                        laserButtonValue = (laserButtonValue == "L") ? "l" : "L"
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
                        if fireButtonValue == "F" {
                            fireButtonValue = "f"
                            triggerButtonValue = "t"
                        } else {
                            fireButtonValue = "F"
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
                    
                    // Tetik Butonu
                    Button(action: {
                        if triggerButtonValue == "T" {
                            triggerButtonValue = "t"
                        } else if fireButtonValue == "F" && triggerButtonValue == "t" {
                            triggerButtonValue = "T"
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
                    
                    // Gyro Kontrol Butonu
                    Button(action: {
                        toggleGyroUpdates()
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
            .padding(.horizontal, 10)
            
            HStack {
                // Sol joystick
                JoystickView(size: 250, joyStickOnChange: { translation in
                    leftJoystickValue = translation
                    updateAndSendCombinedJoystickData()
                }, type: .movement)
                
                Spacer()
                
                // Sağ joystick
                JoystickView(size: 250, joyStickOnChange: { translation in
                    rightJoystickValue = translation
                    updateAndSendCombinedJoystickData()
                }, type: .turret)
            }
        }.padding()
    }
    
    // Joystick verilerini birleştirip Bluetooth'a gönderir
    func updateAndSendCombinedJoystickData() {
        let combinedData = "\(leftJoystickValue);\(rightJoystickValue);\(laserButtonValue)\(fireButtonValue)\(triggerButtonValue)"
        bluetoothManager.updateJoystickValue(value: combinedData)
        debugPrint(combinedData)
    }
    
    // Gelen değerlerin sınırlandırılması
    private func constrain(_ value: Int, min: Int, max: Int) -> Int {
        return Swift.min(Swift.max(value, min), max)
    }
}
