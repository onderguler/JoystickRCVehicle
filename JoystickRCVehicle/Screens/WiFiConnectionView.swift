import SwiftUI

struct WiFiConnectionView: View {
    @ObservedObject var wifiManager: WiFiManager
    let onDisconnect: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("connection_status".localized)) {
                    HStack {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 10, height: 10)
                        Text(statusText)
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("wifi_vehicle_network".localized)) {
                    TextField("wifi_ssid".localized, text: $wifiManager.ssid)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("wifiSSIDField")
                    SecureField("wifi_password".localized, text: $wifiManager.password)
                        .accessibilityIdentifier("wifiPasswordField")
                    TextField("wifi_host".localized, text: $wifiManager.host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                        .accessibilityIdentifier("wifiHostField")
                    TextField("wifi_port".localized, text: $wifiManager.portText)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("wifiPortField")
                }

            }
            .accessibilityIdentifier("wifiConnectionForm")
            .navigationTitle("wifi_connection".localized)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: toggleConnection) {
                        Image(systemName: wifiManager.connectionState.isConnected ? "wifi.slash" : "wifi")
                    }
                    .disabled(wifiManager.connectionState == .connecting)
                    .accessibilityLabel(
                        wifiManager.connectionState.isConnected
                            ? "disconnect".localized
                            : "connect".localized
                    )
                    .accessibilityIdentifier("wifiConnectButton")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityIdentifier("wifiCloseButton")
                }
            }
        }
    }

    private var statusText: String {
        switch wifiManager.connectionState {
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
        switch wifiManager.connectionState {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .disconnected, .failed:
            return .red
        }
    }

    private func toggleConnection() {
        if wifiManager.connectionState.isConnected {
            onDisconnect()
        } else {
            wifiManager.connect()
        }
    }
}
