import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("isHapticFeedbackEnabled") private var isHapticFeedbackEnabled = true
    @AppStorage("movementSensitivity") private var movementSensitivity: Double = 50
    @AppStorage("turretSensitivity") private var turretSensitivity: Double = 50

    @StateObject private var coordinator = ConnectionCoordinator()
    @StateObject private var gyroController = GyroController()

    @State private var showingInfoView = false
    @State private var showingSettingsView = false
    @State private var showingConnectionView = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var wasConnected = false
    @GestureState private var isTriggerTouchDown = false

    var body: some View {
        VStack(spacing: 12) {
            controlToolbar
            Divider()
            commandReadout
            controlSurface
        }
        .padding(16)
        .toast(isPresented: $showToast, message: $toastMessage)
        .sheet(isPresented: $showingInfoView) {
            InfoView()
        }
        .sheet(isPresented: $showingSettingsView) {
            SettingsView()
        }
        .sheet(isPresented: $showingConnectionView) {
            connectionSheet
        }
        .onChange(of: coordinator.connectionState) { state in
            handleConnectionState(state)
        }
        .onChange(of: turretSensitivity) { value in
            gyroController.sensitivity = value
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                stopTransientControls(sendImmediately: true)
            }
        }
    }

    private var controlToolbar: some View {
        HStack(spacing: 12) {
            toolbarButton(
                systemName: "info.circle",
                background: .blue,
                accessibilityLabel: "info_title".localized
            ) {
                triggerHaptic()
                showingInfoView = true
            }
            .accessibilityIdentifier("infoButton")

            toolbarButton(
                systemName: "gearshape",
                background: .blue,
                accessibilityLabel: "settings".localized
            ) {
                triggerHaptic()
                showingSettingsView = true
            }
            .accessibilityIdentifier("settingsButton")

            Spacer(minLength: 8)

            Picker("connection_mode".localized, selection: connectionModeBinding) {
                Text("bluetooth".localized).tag(ConnectionMode.bluetooth)
                Text("wifi".localized).tag(ConnectionMode.wifi)
            }
            .pickerStyle(.segmented)
            .frame(width: 230)
            .accessibilityIdentifier("connectionModePicker")

            Spacer(minLength: 8)

            toolbarButton(
                systemName: connectionIcon,
                background: connectionColor,
                accessibilityLabel: "connection".localized
            ) {
                triggerHaptic()
                showingConnectionView = true
            }
            .accessibilityIdentifier("connectionButton")

            toolbarButton(
                systemName: "gyroscope",
                background: gyroController.isActive ? .red : (coordinator.isConnected ? .blue : .gray),
                accessibilityLabel: "gyro".localized
            ) {
                triggerHaptic()
                toggleGyro()
            }
            .disabled(!gyroController.isAvailable)
            .accessibilityIdentifier("gyroButton")
        }
        .frame(minHeight: 52)
    }

    private var controlSurface: some View {
        GeometryReader { _ in
            HStack(spacing: 12) {
                FloatingJoystickArea(
                    kind: .movement,
                    sensitivity: movementSensitivity,
                    turretPosition: currentTurret,
                    onMovement: updateMovement
                )

                deviceToolbar
                    .frame(width: 88)

                FloatingJoystickArea(
                    kind: .turret,
                    sensitivity: turretSensitivity,
                    turretPosition: currentTurret,
                    isEnabled: !gyroController.isActive,
                    onTurret: updateTurret
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(minHeight: 240)
    }

    private var commandReadout: some View {
        Text(commandPayload)
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .foregroundStyle(coordinator.isConnected ? Color.primary : Color.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityIdentifier("commandReadout")
    }

    private var deviceToolbar: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            deviceButton(
                systemName: "target",
                isActive: coordinator.currentCommand.flags.contains(.laser),
                activeColor: .red,
                size: 64,
                accessibilityLabel: "laser_button".localized,
                identifier: "laserButton",
                action: toggleLaser
            )
            deviceButton(
                systemName: "bolt.fill",
                isActive: coordinator.currentCommand.flags.contains(.fire),
                activeColor: .orange,
                size: 64,
                accessibilityLabel: "fire_button".localized,
                identifier: "fireButton",
                action: toggleFire
            )
            triggerButton
            Spacer(minLength: 0)
        }
    }

    private var triggerButton: some View {
        let isActive = coordinator.currentCommand.flags.contains(.trigger)

        return Image(systemName: "flame.fill")
            .font(.system(size: 28, weight: .semibold))
            .frame(width: 76, height: 76)
            .background(isActive ? Color.red : Color.blue)
            .foregroundColor(.white)
            .clipShape(Circle())
            .scaleEffect(isTriggerTouchDown ? 0.94 : 1)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isTriggerTouchDown) { value, isPressed, _ in
                        let center = CGPoint(x: 38, y: 38)
                        isPressed = hypot(
                            value.location.x - center.x,
                            value.location.y - center.y
                        ) <= 38
                    }
            )
            .onChange(of: isTriggerTouchDown, perform: setTriggerPressed)
            .accessibilityElement()
            .accessibilityLabel("trigger_button".localized)
            .accessibilityValue(isActive ? "active".localized : "inactive".localized)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("triggerButton")
            .help("trigger_button".localized)
    }

    @ViewBuilder
    private var connectionSheet: some View {
        switch coordinator.selectedMode {
        case .bluetooth:
            if let bluetoothManager = coordinator.bluetoothManager {
                BluetoothDeviceListView(
                    bluetoothManager: bluetoothManager,
                    onDisconnect: coordinator.disconnectSelectedTransport
                )
            }
        case .wifi:
            if let wifiManager = coordinator.wifiManager {
                WiFiConnectionView(
                    wifiManager: wifiManager,
                    onDisconnect: coordinator.disconnectSelectedTransport
                )
            }
        }
    }

    private var connectionModeBinding: Binding<ConnectionMode> {
        Binding(
            get: { coordinator.selectedMode },
            set: { mode in
                guard mode != coordinator.selectedMode else { return }
                triggerHaptic()
                wasConnected = false
                gyroController.stop()
                coordinator.selectMode(mode)
            }
        )
    }

    private var currentTurret: TurretPosition {
        TurretPosition(
            x: coordinator.currentCommand.turretX,
            y: coordinator.currentCommand.turretY
        )
    }

    private var commandPayload: String {
        let command = coordinator.currentCommand
        return "\(command.leftMotor),\(command.rightMotor);\(command.turretX),\(command.turretY);\(command.flags.rawValue)"
    }

    private var connectionIcon: String {
        switch coordinator.selectedMode {
        case .bluetooth:
            return coordinator.isConnected ? "cable.connector" : "cable.connector.slash"
        case .wifi:
            return coordinator.isConnected ? "wifi" : "wifi.slash"
        }
    }

    private var connectionColor: Color {
        switch coordinator.connectionState {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .disconnected, .failed:
            return .red
        }
    }

    private func toolbarButton(
        systemName: String,
        background: Color,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 48, height: 48)
                .background(background)
                .foregroundColor(.white)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }

    private func deviceButton(
        systemName: String,
        isActive: Bool,
        activeColor: Color,
        size: CGFloat,
        accessibilityLabel: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 24, weight: .semibold))
                .frame(width: size, height: size)
                .background(isActive ? activeColor : Color.blue)
                .foregroundColor(.white)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier)
        .help(accessibilityLabel)
    }

    private func updateMovement(_ movement: MotorOutput) {
        var command = coordinator.currentCommand
        command.leftMotor = movement.left
        command.rightMotor = movement.right
        coordinator.updateCommand(command)
    }

    private func updateTurret(_ position: TurretPosition) {
        var command = coordinator.currentCommand
        command.turretX = position.x
        command.turretY = position.y
        coordinator.updateCommand(command)
    }

    private func toggleLaser() {
        guard requireConnection() else { return }
        triggerHaptic()
        var command = coordinator.currentCommand
        toggle(.laser, in: &command.flags)
        coordinator.updateCommand(command)
    }

    private func toggleFire() {
        guard requireConnection() else { return }
        triggerHaptic()
        var command = coordinator.currentCommand
        if command.flags.contains(.fire) {
            command.flags.remove([.fire, .trigger])
        } else {
            command.flags.insert(.fire)
        }
        coordinator.updateCommand(command)
    }

    private func setTriggerPressed(_ isPressed: Bool) {
        var command = coordinator.currentCommand

        guard isPressed else {
            guard command.flags.contains(.trigger) else { return }
            command.flags.remove(.trigger)
            coordinator.updateCommand(command)
            return
        }

        guard requireConnection() else { return }
        guard command.flags.contains(.fire) else {
            show(message: "enable_fire_button_first".localized)
            return
        }
        guard !command.flags.contains(.trigger) else { return }

        if isHapticFeedbackEnabled {
            HapticFeedbackManager.shared.triggerImpact(style: .medium)
        }
        command.flags.insert(.trigger)
        coordinator.updateCommand(command)
    }

    private func toggle(_ flag: DeviceFlags, in flags: inout DeviceFlags) {
        if flags.contains(flag) {
            flags.remove(flag)
        } else {
            flags.insert(flag)
        }
    }

    private func toggleGyro() {
        guard requireConnection() else { return }
        if gyroController.isActive {
            gyroController.stop()
            return
        }

        let coordinator = coordinator
        let started = gyroController.start(
            from: currentTurret,
            sensitivity: turretSensitivity
        ) { [weak coordinator] position in
            guard let coordinator else { return }
            var command = coordinator.currentCommand
            command.turretX = position.x
            command.turretY = position.y
            coordinator.updateCommand(command)
        }
        if !started {
            show(message: "gyro_unavailable".localized)
        }
    }

    private func requireConnection() -> Bool {
        guard coordinator.isConnected else {
            show(message: "connect_vehicle_first".localized)
            return false
        }
        return true
    }

    private func handleConnectionState(_ state: VehicleConnectionState) {
        switch state {
        case .connected:
            wasConnected = true
        case .failed(let message):
            stopTransientControls(sendImmediately: false)
            show(message: message)
            wasConnected = false
        case .disconnected:
            if wasConnected {
                stopTransientControls(sendImmediately: false)
                show(message: "device_disconnected".localized)
            }
            wasConnected = false
        case .connecting:
            break
        }
    }

    private func stopTransientControls(sendImmediately: Bool) {
        gyroController.stop()
        coordinator.updateCommand(coordinator.currentCommand.safelyStopped())
        if sendImmediately {
            coordinator.sendCurrentCommand()
        }
    }

    private func triggerHaptic() {
        guard isHapticFeedbackEnabled else { return }
        HapticFeedbackManager.shared.triggerImpact(style: .light)
    }

    private func show(message: String) {
        toastMessage = message
        showToast = true
    }
}
