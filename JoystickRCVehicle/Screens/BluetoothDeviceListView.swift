//
//  BluetoothDeviceListView.swift
//  JoystickRCVehicle
//
//  Created by Onder Guler on 24.09.2024.
//

import SwiftUI

struct BluetoothDeviceListView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @Environment(\.presentationMode) var presentationMode  // Modal kontrolü için kullanılır

    var body: some View {
        NavigationView {
            List(bluetoothManager.peripherals, id: \.identifier) { peripheral in
                Button(action: {
                    bluetoothManager.connect(to: peripheral)
                }) {
                    Text(peripheral.name ?? "Bilinmeyen Cihaz")
                }
            }
            .navigationTitle("Bluetooth Devices")
            
            .onChange(of: bluetoothManager.isConnected) { isConnected in
                if isConnected {
                    presentationMode.wrappedValue.dismiss()  // Bağlantı tamamlandığında ekran kapanır
                }
            }
        }
    }
}
