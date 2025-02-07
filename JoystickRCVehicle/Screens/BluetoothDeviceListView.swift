//
//  BluetoothDeviceListView.swift
//  JoystickRCVehicle
//
//  Created by Onder Guler on 24.09.2024.
//

import SwiftUI

struct BluetoothDeviceListView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @Environment(\.dismiss) var dismiss  // Daha modern modal kontrolü
    
    var body: some View {
        NavigationView {
            if bluetoothManager.peripherals.isEmpty {
                VStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .foregroundColor(.secondary)
                        .padding()

                    Text("no_devices_found".localized)
                        .font(.headline)
                        .foregroundColor(.gray)
                }
                .padding()
            } else {
                List(bluetoothManager.peripherals, id: \.identifier) { peripheral in
                    if let name = peripheral.name {
                        Button(action: {
                            bluetoothManager.connect(to: peripheral)
                        }) {
                            Text(name)
                        }
                    }
                }
            }
        }
        .navigationTitle(Text("bluetooth_devices".localized))
        .onChange(of: bluetoothManager.isConnected) { isConnected in
            if isConnected {
                dismiss()  // Bağlantı tamamlandığında ekran kapanır
            } else {
                print("Bluetooth disconnected.")
            }
        }
    }
}
