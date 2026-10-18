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

    private struct PendingDisconnect {
        let id: UUID
        let sessionID: UUID?
        let watchdog: DispatchWorkItem
        var submissionDrain: DispatchWorkItem?
    }

    private let defaults: UserDefaults
    private let selectedModeKey = "selectedConnectionMode"
    private let disconnectDelay: TimeInterval
    private let submissionDrainDelay: TimeInterval
    private let scheduleDisconnect: (TimeInterval, DispatchWorkItem) -> Void
    private var transports: [ConnectionMode: any VehicleTransport]
    private var pendingDisconnects: [ConnectionMode: PendingDisconnect] = [:]
    private var sendTimer: Timer?
    private var nextSequence: UInt8 = 0

    init(
        bluetoothTransport: (any VehicleTransport)? = nil,
        wifiTransport: (any VehicleTransport)? = nil,
        defaults: UserDefaults = .standard,
        startsSendTimer: Bool = true,
        // Retained argument name for callers. This is a maximum wait, not a
        // fixed delay after enqueueing a stop under transport backpressure.
        disconnectDelay: TimeInterval = 0.5,
        submissionDrainDelay: TimeInterval = 0.06,
        scheduleDisconnect: @escaping (TimeInterval, DispatchWorkItem) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    ) {
        let bluetoothTransport = bluetoothTransport ?? BluetoothManager()
        let wifiTransport = wifiTransport ?? WiFiManager(defaults: defaults)
        let savedMode = defaults.string(forKey: selectedModeKey)
            .flatMap(ConnectionMode.init(rawValue:)) ?? .bluetooth

        self.defaults = defaults
        self.disconnectDelay = max(0, disconnectDelay)
        self.submissionDrainDelay = max(0, submissionDrainDelay)
        self.scheduleDisconnect = scheduleDisconnect
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
        pendingDisconnects.values.forEach {
            $0.watchdog.cancel()
            $0.submissionDrain?.cancel()
        }
    }

    func selectMode(_ mode: ConnectionMode) {
        guard mode != selectedMode else { return }

        currentCommand = currentCommand.safelyStopped()
        safelyDisconnect(mode: selectedMode)

        selectedMode = mode
        defaults.set(mode.rawValue, forKey: selectedModeKey)
        connectionState = transports[mode]?.connectionState ?? .disconnected
    }

    func updateCommand(_ command: VehicleCommand) {
        guard (try? CommandCodec.validate(command)) != nil else { return }
        currentCommand = isStopping(mode: selectedMode) ? command.safelyStopped() : command
    }

    func disconnectSelectedTransport() {
        currentCommand = currentCommand.safelyStopped()
        safelyDisconnect(mode: selectedMode)
    }

    func sendCurrentCommand() {
        guard !isStopping(mode: selectedMode),
              connectionState.isConnected,
              let transport = transports[selectedMode],
              transport.connectionState.isConnected,
              let data = makePacket(for: currentCommand) else { return }
        transport.send(data, completion: nil)
    }

    private func bindTransportStates() {
        for (mode, transport) in transports {
            transport.stateDidChange = { [weak self, weak transport] state in
                let sessionID = transport?.connectionSessionID
                let applyState = { [weak self, weak transport] in
                    guard let self, let transport,
                          transport.connectionSessionID == sessionID else { return }
                    if let pending = self.pendingDisconnects[mode],
                       pending.sessionID != sessionID || !state.isConnected {
                        self.cancelPendingDisconnect(mode: mode)
                    }
                    guard self.selectedMode == mode else { return }
                    let wasConnected = self.connectionState.isConnected
                    self.connectionState = state
                    if wasConnected && !state.isConnected {
                        self.currentCommand = self.currentCommand.safelyStopped()
                    }
                }
                if Thread.isMainThread {
                    applyState()
                } else {
                    DispatchQueue.main.async(execute: applyState)
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

    private func isStopping(mode: ConnectionMode) -> Bool {
        guard let pending = pendingDisconnects[mode] else { return false }
        guard pending.sessionID == transports[mode]?.connectionSessionID else {
            cancelPendingDisconnect(mode: mode)
            return false
        }
        return true
    }

    private func cancelPendingDisconnect(mode: ConnectionMode) {
        let pending = pendingDisconnects.removeValue(forKey: mode)
        pending?.watchdog.cancel()
        pending?.submissionDrain?.cancel()
    }

    private func safelyDisconnect(mode: ConnectionMode) {
        guard let transport = transports[mode], !isStopping(mode: mode) else { return }
        guard transport.connectionState.isConnected,
              let data = makePacket(for: currentCommand.safelyStopped()) else {
            transport.disconnect()
            return
        }

        let id = UUID()
        let watchdog = DispatchWorkItem { [weak self] in
            self?.finishDisconnect(mode: mode, id: id)
        }
        pendingDisconnects[mode] = PendingDisconnect(
            id: id,
            sessionID: transport.connectionSessionID,
            watchdog: watchdog,
            submissionDrain: nil
        )
        scheduleDisconnect(disconnectDelay, watchdog)
        transport.sendStop(data) { [weak self] result in
            // A cancelled/replaced stop is not proof of delivery. Keep waiting
            // for the bounded fallback; a new session will invalidate this stop.
            guard result == .submitted || result == .acknowledged else { return }
            if Thread.isMainThread {
                self?.stopDidComplete(result, mode: mode, id: id)
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.stopDidComplete(result, mode: mode, id: id)
                }
            }
        }
    }

    private func stopDidComplete(_ result: TransportWriteResult, mode: ConnectionMode, id: UUID) {
        guard var pending = pendingDisconnects[mode], pending.id == id else { return }
        if result == .acknowledged {
            finishDisconnect(mode: mode, id: id)
        } else if result == .submitted, pending.submissionDrain == nil {
            // Write-without-response / UDP submission only queues bytes locally.
            // Give those bytes a short drain window AFTER backpressure releases.
            // The overall watchdog still bounds shutdown if the link stays stuck.
            let drain = DispatchWorkItem { [weak self] in
                self?.finishDisconnect(mode: mode, id: id)
            }
            pending.submissionDrain = drain
            pendingDisconnects[mode] = pending
            scheduleDisconnect(submissionDrainDelay, drain)
        }
    }

    private func finishDisconnect(mode: ConnectionMode, id: UUID) {
        guard let pending = pendingDisconnects[mode], pending.id == id else { return }
        // Remove before invoking the transport, whose callbacks may reconnect.
        cancelPendingDisconnect(mode: mode)
        guard let transport = transports[mode],
              transport.connectionSessionID == pending.sessionID else { return }
        transport.disconnect()
    }

    private func makePacket(for command: VehicleCommand) -> Data? {
        guard let data = try? CommandCodec.encode(command, sequence: nextSequence) else {
            return nil
        }
        nextSequence &+= 1
        return data
    }
}
