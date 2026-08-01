import Combine
import Foundation
import Network
import NetworkExtension

final class WiFiManager: ObservableObject, VehicleTransport {
    @Published var ssid: String {
        didSet { defaults.set(ssid, forKey: Keys.ssid) }
    }
    @Published var password: String {
        didSet { KeychainStore.set(password, for: Keys.password) }
    }
    @Published var host: String {
        didSet { defaults.set(host, forKey: Keys.host) }
    }
    @Published var portText: String {
        didSet { defaults.set(portText, forKey: Keys.port) }
    }
    @Published private(set) var connectionState: VehicleConnectionState = .disconnected

    var stateDidChange: ((VehicleConnectionState) -> Void)?

    private enum Keys {
        static let ssid = "wifiVehicleSSID"
        static let password = "wifiVehiclePassword"
        static let host = "wifiVehicleHost"
        static let port = "wifiVehiclePort"
    }

    private let defaults: UserDefaults
    private let networkQueue = DispatchQueue(label: "com.onderguler.JoystickRCVehicle.udp")
    private var connection: NWConnection?
    private var handshakeTimer: DispatchSourceTimer?
    private var heartbeatTimer: DispatchSourceTimer?
    private var session = WiFiSessionEngine()
    private let writeQueue = LatestWriteQueue()
    private var isCommandWriteInFlight = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ssid = defaults.string(forKey: Keys.ssid) ?? "JoystickRCTank"
        password = KeychainStore.string(for: Keys.password) ?? "JoystickRC254"
        host = defaults.string(forKey: Keys.host) ?? "192.168.4.1"
        portText = defaults.string(forKey: Keys.port) ?? "4210"
    }

    func connect() {
        guard !ssid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let port = UInt16(portText),
              port > 0 else {
            updateState(.failed("wifi_configuration_invalid".localized))
            return
        }

        updateState(.connecting)
        let configuration: NEHotspotConfiguration
        if password.isEmpty {
            configuration = NEHotspotConfiguration(ssid: ssid)
        } else {
            configuration = NEHotspotConfiguration(ssid: ssid, passphrase: password, isWEP: false)
        }
        configuration.joinOnce = true

        NEHotspotConfigurationManager.shared.apply(configuration) { [weak self] error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let error, !Self.isAlreadyAssociated(error) {
                    self.updateState(.failed(error.localizedDescription))
                    return
                }
                self.startUDPConnection(host: self.host, port: port)
            }
        }
    }

    func send(_ data: Data, completion: (() -> Void)? = nil) {
        networkQueue.async { [weak self] in
            guard let self, self.session.isConnected, self.connection != nil else {
                DispatchQueue.main.async { completion?() }
                return
            }

            let replacedWrite = self.writeQueue.replace(with: PendingTransportWrite(
                data: data,
                completion: completion
            ))
            if let replacedCompletion = replacedWrite?.completion {
                DispatchQueue.main.async(execute: replacedCompletion)
            }
            self.drainLatestWrite()
        }
    }

    func disconnect() {
        let configuredSSID = ssid
        networkQueue.async { [weak self] in
            self?.cancelNetworkResources()
            self?.publishState(.disconnected)
        }
        NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: configuredSSID)
    }

    private func startUDPConnection(host: String, port: UInt16) {
        networkQueue.async { [weak self] in
            guard let self, let endpointPort = NWEndpoint.Port(rawValue: port) else {
                self?.publishState(.failed("wifi_configuration_invalid".localized))
                return
            }

            self.cancelNetworkResources()
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: endpointPort,
                using: .udp
            )
            self.connection = connection
            connection.stateUpdateHandler = { [weak self, weak connection] state in
                guard let self, connection === self.connection else { return }
                switch state {
                case .ready:
                    self.receiveNextMessage()
                    self.startHandshake()
                case .failed(let error):
                    self.fail(error.localizedDescription)
                case .waiting(let error):
                    self.fail(error.localizedDescription)
                default:
                    break
                }
            }
            connection.start(queue: self.networkQueue)
        }
    }

    private func startHandshake() {
        handshakeTimer?.cancel()
        perform(session.start(at: currentTime))

        let timer = DispatchSource.makeTimerSource(queue: networkQueue)
        timer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.perform(self.session.poll(at: self.currentTime))
        }
        handshakeTimer = timer
        timer.resume()
    }

    private func startHeartbeat() {
        heartbeatTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: networkQueue)
        timer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.perform(self.session.poll(at: self.currentTime))
        }
        heartbeatTimer = timer
        timer.resume()
    }

    private func receiveNextMessage() {
        connection?.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                self.fail(error.localizedDescription)
                return
            }
            if let data, let message = String(data: data, encoding: .utf8) {
                self.handle(message: message)
            }
            if self.connection != nil {
                self.receiveNextMessage()
            }
        }
    }

    private func handle(message: String) {
        perform(session.receive(message, at: currentTime))
    }

    private func perform(_ actions: [WiFiSessionAction]) {
        for action in actions {
            switch action {
            case .sendHello:
                sendRaw("HELLO,2\n")
            case .sendPing:
                sendRaw("PING\n")
            case .connected:
                handshakeTimer?.cancel()
                handshakeTimer = nil
                publishState(.connected)
                startHeartbeat()
            case .failed(.handshakeTimeout):
                fail("wifi_handshake_timeout".localized)
            case .failed(.heartbeatTimeout):
                fail("wifi_heartbeat_timeout".localized)
            }
        }
    }

    private var currentTime: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    private func sendRaw(_ value: String) {
        guard let data = value.data(using: .utf8), let connection else { return }
        connection.send(content: data, completion: .idempotent)
    }

    private func drainLatestWrite() {
        guard session.isConnected,
              !isCommandWriteInFlight,
              let connection,
              let write = writeQueue.takeLatest() else { return }

        isCommandWriteInFlight = true
        connection.send(content: write.data, completion: .contentProcessed { [weak self, weak connection] error in
            guard let self else { return }
            self.networkQueue.async {
                if let completion = write.completion {
                    DispatchQueue.main.async(execute: completion)
                }
                guard let connection, connection === self.connection else { return }

                self.isCommandWriteInFlight = false
                if let error {
                    self.fail(error.localizedDescription)
                    return
                }
                self.drainLatestWrite()
            }
        })
    }

    private func fail(_ message: String) {
        cancelNetworkResources()
        publishState(.failed(message))
    }

    private func cancelNetworkResources() {
        handshakeTimer?.cancel()
        heartbeatTimer?.cancel()
        handshakeTimer = nil
        heartbeatTimer = nil
        session.reset()
        if let pendingCompletion = writeQueue.removeLatest()?.completion {
            DispatchQueue.main.async(execute: pendingCompletion)
        }
        isCommandWriteInFlight = false
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
    }

    private func publishState(_ state: VehicleConnectionState) {
        DispatchQueue.main.async { [weak self] in
            self?.updateState(state)
        }
    }

    private func updateState(_ state: VehicleConnectionState) {
        guard connectionState != state else { return }
        connectionState = state
        stateDidChange?(state)
    }

    private static func isAlreadyAssociated(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NEHotspotConfigurationErrorDomain
            && error.code == NEHotspotConfigurationError.alreadyAssociated.rawValue
    }
}
