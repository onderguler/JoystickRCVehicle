import Combine
import CoreBluetooth
import Foundation

/// Object identity and a per-attempt token are both required. UUID equality of
/// peripherals alone does not distinguish callbacks retained from an old session.
struct BluetoothSessionIdentity {
    private(set) var id: UUID?
    private var peripheralID: ObjectIdentifier?
    private var serviceIDs: Set<ObjectIdentifier> = []
    private var characteristicID: ObjectIdentifier?

    mutating func begin(peripheral: AnyObject) -> UUID {
        let id = UUID()
        self.id = id
        peripheralID = ObjectIdentifier(peripheral)
        serviceIDs = []
        characteristicID = nil
        return id
    }

    func acceptsCurrentPeripheral(_ peripheral: AnyObject) -> Bool {
        id != nil && peripheralID == ObjectIdentifier(peripheral)
    }

    func accepts(peripheral: AnyObject, sessionID: UUID) -> Bool {
        id == sessionID && acceptsCurrentPeripheral(peripheral)
    }

    mutating func registerServices(_ services: [AnyObject], peripheral: AnyObject, sessionID: UUID) -> Bool {
        guard accepts(peripheral: peripheral, sessionID: sessionID) else { return false }
        serviceIDs = Set(services.map { ObjectIdentifier($0) })
        return true
    }

    func accepts(service: AnyObject, peripheral: AnyObject, sessionID: UUID) -> Bool {
        accepts(peripheral: peripheral, sessionID: sessionID) && serviceIDs.contains(ObjectIdentifier(service))
    }

    mutating func select(characteristic: AnyObject, service: AnyObject, peripheral: AnyObject, sessionID: UUID) -> Bool {
        guard accepts(service: service, peripheral: peripheral, sessionID: sessionID),
              characteristicID == nil else { return false }
        characteristicID = ObjectIdentifier(characteristic)
        return true
    }

    func accepts(characteristic: AnyObject, peripheral: AnyObject, sessionID: UUID) -> Bool {
        accepts(peripheral: peripheral, sessionID: sessionID) && characteristicID == ObjectIdentifier(characteristic)
    }

    mutating func invalidate() {
        id = nil
        peripheralID = nil
        serviceIDs = []
        characteristicID = nil
    }
}

/// Shared by the CoreBluetooth adapter and fake-driven regression tests. It
/// returns removed writes so all state is cleared before client callbacks run.
final class BluetoothWriteState {
    private let queue = LatestWriteQueue()
    private var inFlight: PendingTransportWrite?
    private(set) var isStopping = false

    func enqueue(_ write: PendingTransportWrite, isStop: Bool) -> (accepted: Bool, replaced: PendingTransportWrite?) {
        guard !isStopping else { return (false, nil) }
        if isStop { isStopping = true }
        return (true, queue.replace(with: write))
    }

    func takeReadyWrite(requiresResponse: Bool) -> PendingTransportWrite? {
        guard inFlight == nil, let write = queue.takeLatest() else { return nil }
        if requiresResponse { inFlight = write }
        return write
    }

    func takeAcknowledgedWrite() -> PendingTransportWrite? {
        defer { inFlight = nil }
        return inFlight
    }

    func removeAll() -> [PendingTransportWrite] {
        let removed = [inFlight, queue.removeLatest()].compactMap { $0 }
        inFlight = nil
        isStopping = false
        return removed
    }
}

final class BluetoothManager: NSObject, ObservableObject, VehicleTransport {
    @Published private(set) var peripherals: [CBPeripheral] = []
    @Published private(set) var connectionState: VehicleConnectionState = .disconnected

    var stateDidChange: ((VehicleConnectionState) -> Void)?
    var isConnected: Bool { connectionState.isConnected }
    var connectionSessionID: UUID? { session.id }

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writableCharacteristic: CBCharacteristic?
    private var session = BluetoothSessionIdentity()
    private var sessionDelegate: BluetoothSessionDelegate?
    private let writes = BluetoothWriteState()
    // CoreBluetooth's central callbacks contain no attempt token. Do not start
    // another attempt to the same peripheral until its cancellation terminates.
    private var retiringPeripherals: Set<ObjectIdentifier> = []
    private var awaitingRetirement = false
    private let lastConnectedPeripheralKey = "lastConnectedPeripheralIdentifier"

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func connect(to peripheral: CBPeripheral) {
        if connectedPeripheral === peripheral,
           connectionState == .connecting || connectionState.isConnected { return }

        centralManager.stopScan()
        let previousPeripheral = connectedPeripheral
        let cancelledWrites = clearConnection()
        retire(previousPeripheral)

        let id = session.begin(peripheral: peripheral)
        connectedPeripheral = peripheral
        awaitingRetirement = retiringPeripherals.contains(ObjectIdentifier(peripheral))
        let delegate = BluetoothSessionDelegate(owner: self, sessionID: id)
        sessionDelegate = delegate
        peripheral.delegate = delegate
        movePeripheralToTop(peripheral)
        if session.accepts(peripheral: peripheral, sessionID: id) {
            updateState(.connecting)
        }
        if session.accepts(peripheral: peripheral, sessionID: id), !awaitingRetirement {
            centralManager.connect(peripheral, options: nil)
        }
        cancelledWrites.forEach { $0.complete(.cancelled) }
    }

    func send(_ data: Data, completion: (() -> Void)? = nil) {
        enqueue(PendingTransportWrite(data: data, completion: completion), isStop: false)
    }

    func sendStop(_ data: Data, completion: @escaping (TransportWriteResult) -> Void) {
        enqueue(PendingTransportWrite(data: data, completion: nil, resultCompletion: completion), isStop: true)
    }

    private func enqueue(_ write: PendingTransportWrite, isStop: Bool) {
        guard connectionState.isConnected,
              let id = session.id,
              let characteristic = writableCharacteristic,
              let peripheral = connectedPeripheral else {
            write.complete(.cancelled)
            return
        }

        let writeType = writeType(for: characteristic)
        guard write.data.count <= peripheral.maximumWriteValueLength(for: writeType) else {
            failConnection("bluetooth_payload_too_large".localized)
            write.complete(.failed)
            return
        }

        let result = writes.enqueue(write, isStop: isStop)
        guard result.accepted else {
            write.complete(.cancelled)
            return
        }
        result.replaced?.complete(.superseded)
        guard session.accepts(peripheral: peripheral, sessionID: id) else { return }
        drainLatestWrite()
    }

    func disconnect() {
        let peripheral = connectedPeripheral
        let cancelledWrites = clearConnection()
        retire(peripheral)
        updateState(.disconnected)
        startScanningIfAvailable()
        cancelledWrites.forEach { $0.complete(.cancelled) }
    }

    private func startScanningIfAvailable() {
        guard connectedPeripheral == nil, centralManager.state == .poweredOn else { return }
        centralManager.scanForPeripherals(withServices: nil, options: nil)
    }

    /// Never call client completions until the old connection is fully detached.
    private func clearConnection() -> [PendingTransportWrite] {
        session.invalidate()
        connectedPeripheral?.delegate = nil
        sessionDelegate = nil
        connectedPeripheral = nil
        writableCharacteristic = nil
        awaitingRetirement = false
        return writes.removeAll()
    }

    private func retire(_ peripheral: CBPeripheral?) {
        guard let peripheral else { return }
        guard retiringPeripherals.insert(ObjectIdentifier(peripheral)).inserted else { return }
        centralManager.cancelPeripheralConnection(peripheral)
    }

    private func failConnection(_ message: String) {
        let peripheral = connectedPeripheral
        let failedWrites = clearConnection()
        retire(peripheral)
        updateState(.failed(message))
        startScanningIfAvailable()
        failedWrites.forEach { $0.complete(.failed) }
    }

    private func drainLatestWrite() {
        guard connectionState.isConnected,
              let characteristic = writableCharacteristic,
              let peripheral = connectedPeripheral else { return }

        let writeType = writeType(for: characteristic)
        if writeType == .withoutResponse {
            guard peripheral.canSendWriteWithoutResponse,
                  let write = writes.takeReadyWrite(requiresResponse: false) else { return }
            peripheral.writeValue(write.data, for: characteristic, type: writeType)
            write.complete(.submitted)
            return
        }

        guard let write = writes.takeReadyWrite(requiresResponse: true) else { return }
        peripheral.writeValue(write.data, for: characteristic, type: writeType)
    }

    private func writeType(for characteristic: CBCharacteristic) -> CBCharacteristicWriteType {
        characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
    }

    private func updateState(_ state: VehicleConnectionState) {
        guard connectionState != state else { return }
        connectionState = state
        stateDidChange?(state)
    }

    private func movePeripheralToTop(_ peripheral: CBPeripheral) {
        peripherals.removeAll { $0.identifier == peripheral.identifier }
        peripherals.insert(peripheral, at: 0)
    }

    /// A terminal callback for a cancelled attempt is only a barrier, never a
    /// failure/disconnection of a newer attempt (including the same peripheral).
    private func finishRetirement(of peripheral: CBPeripheral) -> Bool {
        guard retiringPeripherals.remove(ObjectIdentifier(peripheral)) != nil else { return false }
        if connectedPeripheral === peripheral, awaitingRetirement {
            awaitingRetirement = false
            centralManager.connect(peripheral, options: nil)
        }
        return true
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central === centralManager else { return }
        switch central.state {
        case .poweredOn:
            startScanningIfAvailable()
        case .poweredOff, .unauthorized, .unsupported, .resetting, .unknown:
            let cancelledWrites = clearConnection()
            retiringPeripherals.removeAll()
            switch central.state {
            case .poweredOff:
                updateState(.failed("bluetooth_powered_off".localized))
            case .unauthorized:
                updateState(.failed("bluetooth_unauthorized".localized))
            case .unsupported:
                updateState(.failed("bluetooth_unsupported".localized))
            default:
                updateState(.disconnected)
            }
            cancelledWrites.forEach { $0.complete(.cancelled) }
        @unknown default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard central === centralManager,
              !peripherals.contains(where: { $0.identifier == peripheral.identifier }) else { return }

        if peripheral.identifier.uuidString == UserDefaults.standard.string(forKey: lastConnectedPeripheralKey) {
            peripherals.insert(peripheral, at: 0)
        } else {
            peripherals.append(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard central === centralManager,
              !retiringPeripherals.contains(ObjectIdentifier(peripheral)),
              !awaitingRetirement,
              session.acceptsCurrentPeripheral(peripheral),
              let id = session.id,
              connectionState == .connecting else { return }
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: lastConnectedPeripheralKey)
        movePeripheralToTop(peripheral)
        guard session.accepts(peripheral: peripheral, sessionID: id) else { return }
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard central === centralManager, !finishRetirement(of: peripheral),
              session.acceptsCurrentPeripheral(peripheral) else { return }
        let cancelledWrites = clearConnection()
        updateState(error.map { .failed($0.localizedDescription) } ?? .disconnected)
        startScanningIfAvailable()
        cancelledWrites.forEach { $0.complete(.cancelled) }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard central === centralManager, !finishRetirement(of: peripheral),
              session.acceptsCurrentPeripheral(peripheral) else { return }
        let cancelledWrites = clearConnection()
        updateState(.failed(error?.localizedDescription ?? "device_connection_failed".localized))
        startScanningIfAvailable()
        cancelledWrites.forEach { $0.complete(.failed) }
    }
}

extension BluetoothManager {
    fileprivate func didDiscoverServices(_ peripheral: CBPeripheral, error: Error?, sessionID: UUID) {
        guard session.accepts(peripheral: peripheral, sessionID: sessionID),
              !awaitingRetirement, connectionState == .connecting else { return }
        if let error {
            failConnection(error.localizedDescription)
            return
        }
        let services = peripheral.services ?? []
        guard session.registerServices(services, peripheral: peripheral, sessionID: sessionID) else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    fileprivate func didDiscoverCharacteristics(_ peripheral: CBPeripheral, service: CBService, error: Error?, sessionID: UUID) {
        guard session.accepts(service: service, peripheral: peripheral, sessionID: sessionID),
              !awaitingRetirement, writableCharacteristic == nil else { return }
        if let error {
            failConnection(error.localizedDescription)
            return
        }
        guard let characteristic = service.characteristics?.first(where: {
            $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse)
        }), session.select(characteristic: characteristic, service: service, peripheral: peripheral, sessionID: sessionID) else { return }

        writableCharacteristic = characteristic
        updateState(.connected)
    }

    fileprivate func didWriteValue(_ peripheral: CBPeripheral, characteristic: CBCharacteristic, error: Error?, sessionID: UUID) {
        guard session.accepts(characteristic: characteristic, peripheral: peripheral, sessionID: sessionID),
              !awaitingRetirement,
              writeType(for: characteristic) == .withResponse,
              let completedWrite = writes.takeAcknowledgedWrite() else { return }
        if let error {
            failConnection(error.localizedDescription)
            completedWrite.complete(.failed)
            return
        }
        completedWrite.complete(.acknowledged)
        guard session.accepts(characteristic: characteristic, peripheral: peripheral, sessionID: sessionID) else { return }
        drainLatestWrite()
    }

    fileprivate func readyToSend(_ peripheral: CBPeripheral, sessionID: UUID) {
        guard session.accepts(peripheral: peripheral, sessionID: sessionID), !awaitingRetirement else { return }
        drainLatestWrite()
    }
}

/// Each delegate forwards the token of the session that created it, so already
/// enqueued callbacks cannot be reinterpreted as belonging to a newer session.
private final class BluetoothSessionDelegate: NSObject, CBPeripheralDelegate {
    private weak var owner: BluetoothManager?
    private let sessionID: UUID

    init(owner: BluetoothManager, sessionID: UUID) {
        self.owner = owner
        self.sessionID = sessionID
        super.init()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        owner?.didDiscoverServices(peripheral, error: error, sessionID: sessionID)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        owner?.didDiscoverCharacteristics(peripheral, service: service, error: error, sessionID: sessionID)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        owner?.didWriteValue(peripheral, characteristic: characteristic, error: error, sessionID: sessionID)
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        owner?.readyToSend(peripheral, sessionID: sessionID)
    }
}
