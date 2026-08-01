import Combine
import Foundation

final class ConnectionCoordinator: ObservableObject {
    static let sendInterval: TimeInterval = 0.025

    @Published private(set) var selectedMode: ConnectionMode
    @Published private(set) var connectionState: VehicleConnectionState
    @Published private(set) var currentCommand: VehicleCommand = .neutral

    var bluetoothManager: BluetoothManager? {
        transports[.bluetooth] as? BluetoothManager
    }

    var wifiManager: WiFiManager? {
        transports[.wifi] as? WiFiManager
    }

    var isConnected: Bool { connectionState.isConnected }

    private let defaults: UserDefaults
    private let selectedModeKey = "selectedConnectionMode"
    private let disconnectDelay: TimeInterval
    private var transports: [ConnectionMode: any VehicleTransport]
    private var sendTimer: Timer?
    private var nextSequence: UInt8 = 0

    init(
        bluetoothTransport: (any VehicleTransport)? = nil,
        wifiTransport: (any VehicleTransport)? = nil,
        defaults: UserDefaults = .standard,
        startsSendTimer: Bool = true,
        disconnectDelay: TimeInterval = 0.06
    ) {
        let bluetoothTransport = bluetoothTransport ?? BluetoothManager()
        let wifiTransport = wifiTransport ?? WiFiManager(defaults: defaults)
        let savedMode = defaults.string(forKey: selectedModeKey)
            .flatMap(ConnectionMode.init(rawValue:)) ?? .bluetooth

        self.defaults = defaults
        self.disconnectDelay = disconnectDelay
        self.transports = [
            .bluetooth: bluetoothTransport,
            .wifi: wifiTransport
        ]
        selectedMode = savedMode
        connectionState = self.transports[savedMode]?.connectionState ?? .disconnected

        bindTransportStates()
        if startsSendTimer {
            startSendTimer()
        }
    }

    deinit {
        sendTimer?.invalidate()
    }

    func selectMode(_ mode: ConnectionMode) {
        guard mode != selectedMode else { return }

        let previousMode = selectedMode
        let previousTransport = transports[previousMode]
        currentCommand = currentCommand.safelyStopped()
        safelyDisconnect(previousTransport)

        selectedMode = mode
        defaults.set(mode.rawValue, forKey: selectedModeKey)
        connectionState = transports[mode]?.connectionState ?? .disconnected
    }

    func updateCommand(_ command: VehicleCommand) {
        guard (try? CommandCodec.validate(command)) != nil else { return }
        currentCommand = command
    }

    func disconnectSelectedTransport() {
        currentCommand = currentCommand.safelyStopped()
        safelyDisconnect(transports[selectedMode])
    }

    func sendCurrentCommand() {
        guard connectionState.isConnected,
              let transport = transports[selectedMode],
              let data = makePacket(for: currentCommand) else { return }
        transport.send(data, completion: nil)
    }

    private func bindTransportStates() {
        for (mode, transport) in transports {
            transport.stateDidChange = { [weak self] state in
                DispatchQueue.main.async {
                    guard let self, self.selectedMode == mode else { return }
                    let wasConnected = self.connectionState.isConnected
                    self.connectionState = state
                    if wasConnected && !state.isConnected {
                        self.currentCommand = self.currentCommand.safelyStopped()
                    }
                }
            }
        }
    }

    private func startSendTimer() {
        let timer = Timer(timeInterval: Self.sendInterval, repeats: true) { [weak self] _ in
            self?.sendCurrentCommand()
        }
        timer.tolerance = Self.sendInterval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        sendTimer = timer
    }

    private func safelyDisconnect(_ transport: (any VehicleTransport)?) {
        guard let transport else { return }
        guard transport.connectionState.isConnected,
              let data = makePacket(for: currentCommand.safelyStopped()) else {
            transport.disconnect()
            return
        }

        transport.send(data, completion: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + disconnectDelay) {
            transport.disconnect()
        }
    }

    private func makePacket(for command: VehicleCommand) -> Data? {
        guard let data = try? CommandCodec.encode(command, sequence: nextSequence) else {
            return nil
        }
        nextSequence &+= 1
        return data
    }
}
