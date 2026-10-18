import Combine
import Foundation
import Network
import NetworkExtension

struct WiFiConnectionConfiguration: Equatable {
    let ssid: String
    let password: String
    let host: String
    let port: UInt16
}

protocol WiFiHotspotJoining {
    func apply(_ configuration: WiFiConnectionConfiguration, completion: @escaping (Error?) -> Void)
    func removeConfiguration(forSSID ssid: String)
}

enum WiFiUDPState {
    case ready
    case failed(Error)
}

protocol WiFiUDPConnection: AnyObject {
    var stateUpdateHandler: ((WiFiUDPState) -> Void)? { get set }
    func start(queue: DispatchQueue)
    func receiveMessage(completion: @escaping (Data?, Error?) -> Void)
    func send(_ data: Data, completion: ((Error?) -> Void)?)
    func cancel()
}

protocol WiFiPollTimer {
    func cancel()
}

private struct SystemWiFiHotspot: WiFiHotspotJoining {
    func apply(_ snapshot: WiFiConnectionConfiguration, completion: @escaping (Error?) -> Void) {
        let configuration: NEHotspotConfiguration
        if snapshot.password.isEmpty {
            configuration = NEHotspotConfiguration(ssid: snapshot.ssid)
        } else {
            configuration = NEHotspotConfiguration(
                ssid: snapshot.ssid, passphrase: snapshot.password, isWEP: false
            )
        }
        configuration.joinOnce = true
        NEHotspotConfigurationManager.shared.apply(configuration, completionHandler: completion)
    }

    func removeConfiguration(forSSID ssid: String) {
        NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
    }
}

private final class SystemWiFiUDPConnection: WiFiUDPConnection {
    var stateUpdateHandler: ((WiFiUDPState) -> Void)?
    private let connection: NWConnection

    init(host: String, port: UInt16) {
        // The configuration snapshot has already rejected port zero.
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .udp)
    }

    func start(queue: DispatchQueue) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.stateUpdateHandler?(.ready)
            case .failed(let error), .waiting(let error):
                self?.stateUpdateHandler?(.failed(error))
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func receiveMessage(completion: @escaping (Data?, Error?) -> Void) {
        connection.receiveMessage { data, _, _, error in completion(data, error) }
    }

    func send(_ data: Data, completion: ((Error?) -> Void)?) {
        if let completion {
            connection.send(content: data, completion: .contentProcessed { completion($0) })
        } else {
            connection.send(content: data, completion: .idempotent)
        }
    }

    func cancel() {
        connection.stateUpdateHandler = nil
        connection.cancel()
    }
}

private final class SystemWiFiPollTimer: WiFiPollTimer {
    private let timer: DispatchSourceTimer

    init(queue: DispatchQueue, handler: @escaping () -> Void) {
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250))
        timer.setEventHandler(handler: handler)
        timer.resume()
    }

    func cancel() { timer.cancel() }
    deinit { timer.cancel() }
}

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
    var connectionSessionID: UUID? { onNetworkQueue { activeSessionID } }

    private enum Keys {
        static let ssid = "wifiVehicleSSID"
        static let password = "wifiVehiclePassword"
        static let host = "wifiVehicleHost"
        static let port = "wifiVehiclePort"
    }

    private struct InFlightWrite {
        let id = UUID()
        let write: PendingTransportWrite
    }

    private let defaults: UserDefaults
    private let hotspot: any WiFiHotspotJoining
    private let makeConnection: (String, UInt16) -> any WiFiUDPConnection
    private let makeTimer: (DispatchQueue, @escaping () -> Void) -> any WiFiPollTimer
    private let now: () -> TimeInterval
    private let networkQueue: DispatchQueue
    private let networkQueueKey = DispatchSpecificKey<Bool>()

    // UI configuration/connect/disconnect live on main. All lifecycle and UDP
    // resources below live on networkQueue, including synchronous invalidation.
    private var generation = UUID()
    private var activeSessionID: UUID?
    private var configuredSSID: String?
    private var connection: (any WiFiUDPConnection)?
    private var pollTimer: (any WiFiPollTimer)?
    private var session = WiFiSessionEngine()
    private let writeQueue = LatestWriteQueue()
    private var inFlightWrite: InFlightWrite?
    private var isStopping = false

    convenience init(defaults: UserDefaults = .standard) {
        self.init(
            defaults: defaults,
            hotspot: SystemWiFiHotspot(),
            makeConnection: { SystemWiFiUDPConnection(host: $0, port: $1) },
            makeTimer: { SystemWiFiPollTimer(queue: $0, handler: $1) }
        )
    }

    init(
        defaults: UserDefaults,
        hotspot: any WiFiHotspotJoining,
        makeConnection: @escaping (String, UInt16) -> any WiFiUDPConnection,
        makeTimer: @escaping (DispatchQueue, @escaping () -> Void) -> any WiFiPollTimer,
        networkQueue: DispatchQueue = DispatchQueue(label: "com.onderguler.JoystickRCVehicle.udp"),
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.defaults = defaults
        self.hotspot = hotspot
        self.makeConnection = makeConnection
        self.makeTimer = makeTimer
        self.networkQueue = networkQueue
        self.now = now
        ssid = defaults.string(forKey: Keys.ssid) ?? "JoystickRCTank"
        password = KeychainStore.string(for: Keys.password) ?? "JoystickRC254"
        host = defaults.string(forKey: Keys.host) ?? "192.168.4.1"
        portText = defaults.string(forKey: Keys.port) ?? "4210"
        networkQueue.setSpecific(key: networkQueueKey, value: true)
    }

    deinit {
        onNetworkQueue { cancelNetworkResources() }
    }

    func connect() {
        // Revoke the entire previous attempt before publishing or starting work.
        let attemptID = onNetworkQueue { invalidateSession() }
        guard !ssid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let port = UInt16(portText), port > 0 else {
            updateState(.failed("wifi_configuration_invalid".localized))
            return
        }
        let snapshot = WiFiConnectionConfiguration(ssid: ssid, password: password, host: host, port: port)
        let previousSSID = onNetworkQueue { () -> String? in
            let previousSSID = configuredSSID
            activeSessionID = attemptID
            configuredSSID = snapshot.ssid
            return previousSSID
        }
        if let previousSSID, previousSSID != snapshot.ssid {
            hotspot.removeConfiguration(forSSID: previousSSID)
        }
        updateState(.connecting)
        guard onNetworkQueue({ isCurrent(attemptID) }) else { return }

        hotspot.apply(snapshot) { [weak self] error in
            guard let self else { return }
            self.networkQueue.async {
                guard self.isCurrent(attemptID) else { return }
                if let error, !Self.isAlreadyAssociated(error) {
                    self.fail(error.localizedDescription, attemptID: attemptID)
                    return
                }
                self.startUDPConnection(configuration: snapshot, attemptID: attemptID)
            }
        }
    }

    func send(_ data: Data, completion: (() -> Void)? = nil) {
        enqueue(PendingTransportWrite(data: data, completion: completion), isStop: false)
    }

    func sendStop(_ data: Data, completion: @escaping (TransportWriteResult) -> Void) {
        enqueue(PendingTransportWrite(data: data, completion: nil, resultCompletion: completion), isStop: true)
    }

    private func enqueue(_ write: PendingTransportWrite, isStop: Bool) {
        let attemptID = connectionSessionID
        networkQueue.async { [weak self] in
            guard let self, let attemptID, self.isCurrent(attemptID), self.session.isConnected,
                  self.connection != nil, !self.isStopping else {
                DispatchQueue.main.async { write.complete(.cancelled) }
                return
            }
            if isStop { self.isStopping = true }
            if let replacedWrite = self.writeQueue.replace(with: write) {
                self.complete(replacedWrite, with: .superseded)
            }
            self.drainLatestWrite(attemptID: attemptID)
        }
    }

    func disconnect() {
        let ssidToRemove = onNetworkQueue { () -> String? in
            let previousSSID = configuredSSID
            _ = invalidateSession()
            configuredSSID = nil
            return previousSSID
        }
        if let ssidToRemove { hotspot.removeConfiguration(forSSID: ssidToRemove) }
        updateState(.disconnected)
    }

    private func startUDPConnection(configuration: WiFiConnectionConfiguration, attemptID: UUID) {
        guard isCurrent(attemptID), connection == nil else { return }
        let connection = makeConnection(configuration.host, configuration.port)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            self.networkQueue.async {
                guard self.isCurrent(attemptID, connection: connection) else { return }
                switch state {
                case .ready:
                    self.startHandshake(attemptID: attemptID, connection: connection)
                    self.receiveNextMessage(attemptID: attemptID, connection: connection)
                case .failed(let error):
                    self.fail(error.localizedDescription, attemptID: attemptID)
                }
            }
        }
        connection.start(queue: networkQueue)
    }

    private func startHandshake(attemptID: UUID, connection: any WiFiUDPConnection) {
        guard isCurrent(attemptID, connection: connection) else { return }
        pollTimer?.cancel()
        perform(session.start(at: now()), attemptID: attemptID, connection: connection)
        pollTimer = makeTimer(networkQueue) { [weak self, weak connection] in
            guard let self, let connection else { return }
            self.networkQueue.async {
                guard self.isCurrent(attemptID, connection: connection) else { return }
                self.perform(self.session.poll(at: self.now()), attemptID: attemptID, connection: connection)
            }
        }
    }

    private func receiveNextMessage(attemptID: UUID, connection: any WiFiUDPConnection) {
        guard isCurrent(attemptID, connection: connection) else { return }
        connection.receiveMessage { [weak self, weak connection] data, error in
            guard let self, let connection else { return }
            self.networkQueue.async {
                // Never feed an old datagram/error into a replacement session or
                // recursively register a receive on its connection.
                guard self.isCurrent(attemptID, connection: connection) else { return }
                if let error {
                    self.fail(error.localizedDescription, attemptID: attemptID)
                    return
                }
                if let data, let message = String(data: data, encoding: .utf8) {
                    self.perform(self.session.receive(message, at: self.now()), attemptID: attemptID, connection: connection)
                }
                self.receiveNextMessage(attemptID: attemptID, connection: connection)
            }
        }
    }

    private func perform(_ actions: [WiFiSessionAction], attemptID: UUID, connection: any WiFiUDPConnection) {
        for action in actions {
            guard isCurrent(attemptID, connection: connection) else { return }
            switch action {
            case .sendHello:
                connection.send(Data("HELLO,2\n".utf8), completion: nil)
            case .sendPing:
                connection.send(Data("PING\n".utf8), completion: nil)
            case .connected:
                publishState(.connected, generation: attemptID)
            case .failed(.handshakeTimeout):
                fail("wifi_handshake_timeout".localized, attemptID: attemptID)
            case .failed(.heartbeatTimeout):
                fail("wifi_heartbeat_timeout".localized, attemptID: attemptID)
            }
        }
    }

    private func drainLatestWrite(attemptID: UUID) {
        guard isCurrent(attemptID), session.isConnected, inFlightWrite == nil,
              let connection, let write = writeQueue.takeLatest() else { return }
        let inFlight = InFlightWrite(write: write)
        inFlightWrite = inFlight
        connection.send(write.data) { [weak self, weak connection] error in
            guard let self, let connection else { return }
            self.networkQueue.async {
                guard self.isCurrent(attemptID, connection: connection),
                      self.inFlightWrite?.id == inFlight.id else { return }
                self.inFlightWrite = nil
                self.complete(write, with: error == nil ? .submitted : .failed)
                if let error {
                    self.fail(error.localizedDescription, attemptID: attemptID)
                    return
                }
                self.drainLatestWrite(attemptID: attemptID)
            }
        }
    }

    private func complete(_ write: PendingTransportWrite, with result: TransportWriteResult) {
        DispatchQueue.main.async { write.complete(result) }
    }

    private func fail(_ message: String, attemptID: UUID) {
        guard isCurrent(attemptID) else { return }
        let failureGeneration = invalidateSession()
        publishState(.failed(message), generation: failureGeneration)
    }

    @discardableResult
    private func invalidateSession() -> UUID {
        generation = UUID()
        activeSessionID = nil
        // Retain the applied SSID after failure so disconnect can still remove it.
        // A replacement removes the previous configuration if its SSID changes.
        cancelNetworkResources()
        return generation
    }

    private func cancelNetworkResources() {
        pollTimer?.cancel()
        pollTimer = nil
        session.reset()
        if let pendingWrite = writeQueue.removeLatest() { complete(pendingWrite, with: .cancelled) }
        if let inFlightWrite { complete(inFlightWrite.write, with: .cancelled) }
        inFlightWrite = nil
        isStopping = false
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
    }

    private func isCurrent(_ attemptID: UUID, connection candidate: (any WiFiUDPConnection)? = nil) -> Bool {
        guard generation == attemptID, activeSessionID == attemptID else { return false }
        return candidate == nil || candidate === connection
    }

    private func onNetworkQueue<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: networkQueueKey) == true { return body() }
        return networkQueue.sync(execute: body)
    }

    private func publishState(_ state: VehicleConnectionState, generation expectedGeneration: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.onNetworkQueue({ self.generation == expectedGeneration }) else { return }
            self.updateState(state)
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
