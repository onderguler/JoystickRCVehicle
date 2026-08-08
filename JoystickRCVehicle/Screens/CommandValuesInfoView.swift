import SwiftUI

struct CommandValuesInfoView: View {
    var body: some View {
        List {
            Section {
                Label {
                    Text("sent_values_overview".localized)
                        .foregroundColor(.secondary)
                        .accessibilityIdentifier("sentValuesScreen")
                } icon: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(.blue)
                }
            }

            Section(header: Text("motor_values".localized)) {
                valueRow(
                    icon: "gauge.with.dots.needle.50percent",
                    color: .green,
                    title: "left_motor".localized,
                    range: "-99...99",
                    description: "motor_value_description".localized
                )
                valueRow(
                    icon: "gauge.with.dots.needle.50percent",
                    color: .green,
                    title: "right_motor".localized,
                    range: "-99...99",
                    description: "motor_value_description".localized
                )
            }

            Section(header: Text("turret_values".localized)) {
                valueRow(
                    icon: "arrow.left.and.right",
                    color: .orange,
                    title: "turret_horizontal".localized,
                    range: "-254...254",
                    description: "turret_horizontal_description".localized
                )
                valueRow(
                    icon: "arrow.up.and.down",
                    color: .orange,
                    title: "turret_vertical".localized,
                    range: "-254...254",
                    description: "turret_vertical_description".localized
                )
                Label("turret_target_preserved".localized, systemImage: "pin.fill")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("device_flag_values".localized)) {
                flagRow(icon: "scope", title: "laser".localized, value: "1")
                flagRow(icon: "flame.fill", title: "fire".localized, value: "2")
                flagRow(icon: "button.programmable", title: "trigger".localized, value: "4")
                Text("device_flags_description".localized)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("binary_packet".localized),
                    footer: Text("binary_packet_footer".localized)) {
                packetRow(byte: "0", title: "packet_header".localized, value: "0xA2")
                packetRow(byte: "1", title: "packet_sequence".localized, value: "0...255")
                packetRow(byte: "2", title: "left_motor".localized, value: "Int8")
                packetRow(byte: "3", title: "right_motor".localized, value: "Int8")
                packetRow(byte: "4-5", title: "turret_horizontal".localized, value: "Int16 LE")
                packetRow(byte: "6-7", title: "turret_vertical".localized, value: "Int16 LE")
                packetRow(byte: "8", title: "device_flags".localized, value: "0...7")
                packetRow(byte: "9", title: "packet_crc".localized, value: "CRC-8")
            }

            Section(header: Text("value_processing".localized)) {
                explanationRow(
                    icon: "slider.horizontal.3",
                    title: "sensitivity_processing".localized,
                    description: "sensitivity_processing_description".localized
                )
                explanationRow(
                    icon: "gyroscope",
                    title: "gyro_processing".localized,
                    description: "gyro_processing_description".localized
                )
            }

            Section(header: Text("bluetooth_transport".localized)) {
                explanationRow(
                    icon: "dot.radiowaves.left.and.right",
                    title: "bluetooth_characteristic".localized,
                    description: "bluetooth_characteristic_description".localized
                )
                explanationRow(
                    icon: "arrow.down.to.line.compact",
                    title: "bluetooth_write_mode".localized,
                    description: "bluetooth_write_mode_description".localized
                )
                explanationRow(
                    icon: "ruler",
                    title: "bluetooth_mtu".localized,
                    description: "bluetooth_mtu_description".localized
                )
            }

            Section(header: Text("wifi_transport".localized)) {
                explanationRow(
                    icon: "wifi",
                    title: "wifi_configuration_values".localized,
                    description: "wifi_configuration_values_description".localized
                )
                messageRow(outgoing: "HELLO,2", incoming: "READY,2", detail: "wifi_handshake_description".localized)
                messageRow(outgoing: "PING", incoming: "PONG", detail: "wifi_heartbeat_description".localized)
            }

            Section(header: Text("communication_safety".localized)) {
                safetyRow(icon: "timer", title: "send_interval".localized, value: "25 ms / 40 Hz")
                safetyRow(icon: "arrow.triangle.2.circlepath", title: "latest_command".localized, value: "latest-wins")
                safetyRow(icon: "checkmark.shield", title: "packet_validation".localized, value: "CRC-8")
                safetyRow(icon: "stop.circle", title: "watchdog".localized, value: "250 ms")
                Text("safe_stop_description".localized)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("sent_values".localized)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func valueRow(
        icon: String,
        color: Color,
        title: String,
        range: String,
        description: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Text(range)
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                Text(description)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private func flagRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit())
                .foregroundColor(.secondary)
        }
    }

    private func packetRow(byte: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(byte)
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 34, alignment: .leading)
            Text(title)
            Spacer()
            Text(value)
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
        }
    }

    private func safetyRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundColor(.secondary)
        }
    }

    private func explanationRow(icon: String, title: String, description: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        } icon: {
            Image(systemName: icon)
                .foregroundColor(.blue)
        }
        .padding(.vertical, 3)
    }

    private func messageRow(outgoing: String, incoming: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(outgoing)
                    .font(.caption.monospaced())
                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)
                Text(incoming)
                    .font(.caption.monospaced())
            }
            Text(detail)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 3)
    }
}

#Preview {
    NavigationView {
        CommandValuesInfoView()
    }
}
