import SwiftUI

struct BluetoothDeviceListView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    let onDisconnect: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("connection_status".localized)) {
                    HStack {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 10, height: 10)
                        Text(statusText)
                            .foregroundColor(.secondary)
                    }

                    if bluetoothManager.connectionState.isConnected {
                        Button(role: .destructive, action: onDisconnect) {
                            Label("disconnect".localized, systemImage: "cable.connector.slash")
                        }
                    }
                }

                Section(header: Text("bluetooth_devices".localized)) {
                    if bluetoothManager.peripherals.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 12) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 44))
                                    .foregroundColor(.secondary)
                                Text("no_devices_found".localized)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 32)
                            Spacer()
                        }
                    } else {
                        ForEach(bluetoothManager.peripherals, id: \.identifier) { peripheral in
                            if let name = peripheral.name, !name.isEmpty {
                                Button(action: { bluetoothManager.connect(to: peripheral) }) {
                                    Text(name)
                                }
                            }
                        }
                    }
                }
            }
            .accessibilityIdentifier("bluetoothDeviceList")
            .navigationTitle("bluetooth_devices".localized)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityIdentifier("bluetoothCloseButton")
                }
            }
        }
        .onChange(of: bluetoothManager.connectionState) { state in
            if state.isConnected {
                dismiss()
            }
        }
    }

    private var statusText: String {
        switch bluetoothManager.connectionState {
        case .disconnected:
            return "disconnected".localized
        case .connecting:
            return "connecting".localized
        case .connected:
            return "connected".localized
        case .failed(let message):
            return message
        }
    }

    private var statusColor: Color {
        switch bluetoothManager.connectionState {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .disconnected, .failed:
            return .red
        }
    }
}
