import Combine
import CoreBluetooth
import Foundation

final class BluetoothManager: NSObject, ObservableObject, VehicleTransport {
    @Published private(set) var peripherals: [CBPeripheral] = []
    @Published private(set) var connectionState: VehicleConnectionState = .disconnected

    var stateDidChange: ((VehicleConnectionState) -> Void)?
    var isConnected: Bool { connectionState.isConnected }

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writableCharacteristic: CBCharacteristic?
    private let writeQueue = LatestWriteQueue()
    private var inFlightWrite: PendingTransportWrite?
    private let lastConnectedPeripheralKey = "lastConnectedPeripheralIdentifier"

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func connect(to peripheral: CBPeripheral) {
        centralManager.stopScan()
        connectedPeripheral = peripheral
        writableCharacteristic = nil
        peripheral.delegate = self
        movePeripheralToTop(peripheral)
        updateState(.connecting)
        centralManager.connect(peripheral, options: nil)
    }

    func send(_ data: Data, completion: (() -> Void)? = nil) {
        guard connectionState.isConnected,
              let characteristic = writableCharacteristic,
              let peripheral = connectedPeripheral else {
            completion?()
            return
        }

        let writeType = writeType(for: characteristic)
        guard data.count <= peripheral.maximumWriteValueLength(for: writeType) else {
            updateState(.failed("bluetooth_payload_too_large".localized))
            completion?()
            return
        }

        let replacedWrite = writeQueue.replace(with: PendingTransportWrite(
            data: data,
            completion: completion
        ))
        replacedWrite?.completion?()
        drainLatestWrite()
    }

    func disconnect() {
        let peripheral = connectedPeripheral
        clearConnection()
        if let peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        updateState(.disconnected)
        startScanningIfAvailable()
    }

    private func startScanningIfAvailable() {
        guard centralManager.state == .poweredOn else { return }
        centralManager.scanForPeripherals(withServices: nil, options: nil)
    }

    private func clearConnection() {
        inFlightWrite?.completion?()
        writeQueue.removeLatest()?.completion?()
        inFlightWrite = nil
        connectedPeripheral = nil
        writableCharacteristic = nil
    }

    private func drainLatestWrite() {
        guard connectionState.isConnected,
              let characteristic = writableCharacteristic,
              let peripheral = connectedPeripheral else { return }

        let writeType = writeType(for: characteristic)
        if writeType == .withoutResponse {
            guard peripheral.canSendWriteWithoutResponse,
                  let write = writeQueue.takeLatest() else { return }
            peripheral.writeValue(write.data, for: characteristic, type: writeType)
            write.completion?()
            return
        }

        guard inFlightWrite == nil,
              let write = writeQueue.takeLatest() else { return }
        inFlightWrite = write
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
}

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            startScanningIfAvailable()
        case .poweredOff:
            clearConnection()
            updateState(.failed("bluetooth_powered_off".localized))
        case .unauthorized:
            clearConnection()
            updateState(.failed("bluetooth_unauthorized".localized))
        case .unsupported:
            clearConnection()
            updateState(.failed("bluetooth_unsupported".localized))
        default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard !peripherals.contains(where: { $0.identifier == peripheral.identifier }) else { return }

        if peripheral.identifier.uuidString == UserDefaults.standard.string(forKey: lastConnectedPeripheralKey) {
            peripherals.insert(peripheral, at: 0)
        } else {
            peripherals.append(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: lastConnectedPeripheralKey)
        movePeripheralToTop(peripheral)
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        clearConnection()
        if let error {
            updateState(.failed(error.localizedDescription))
        } else {
            updateState(.disconnected)
        }
        startScanningIfAvailable()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        clearConnection()
        updateState(.failed(error?.localizedDescription ?? "device_connection_failed".localized))
        startScanningIfAvailable()
    }
}

extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            updateState(.failed(error.localizedDescription))
            return
        }
        peripheral.services?.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            updateState(.failed(error.localizedDescription))
            return
        }

        guard writableCharacteristic == nil else { return }
        guard let characteristic = service.characteristics?.first(where: {
            $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse)
        }) else { return }

        writableCharacteristic = characteristic
        updateState(.connected)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let completedWrite = inFlightWrite
        inFlightWrite = nil
        completedWrite?.completion?()
        if let error {
            updateState(.failed(error.localizedDescription))
            return
        }
        drainLatestWrite()
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        drainLatestWrite()
    }
}
