import Foundation
import Testing
@testable import JoystickRCVehicle

struct CommandCodecTests {
    @Test func binaryV2PacketIsExactlyTenBytes() throws {
        let command = VehicleCommand(
            leftMotor: -99,
            rightMotor: -99,
            turretX: -254,
            turretY: -254,
            flags: .all
        )

        let data = try CommandCodec.encode(command, sequence: 0x7F)

        #expect(data == Data([0xA2, 0x7F, 0x9D, 0x9D, 0x02, 0xFF, 0x02, 0xFF, 0x07, 0x07]))
        #expect(data.count == CommandCodec.packetSize)
        #expect(try CommandCodec.decode(data) == VehicleCommandPacket(sequence: 0x7F, command: command))
    }

    @Test func flagsRoundTripAsBitMask() throws {
        let command = VehicleCommand(
            leftMotor: 20,
            rightMotor: 35,
            turretX: -10,
            turretY: 5,
            flags: [.laser, .fire]
        )

        let data = try CommandCodec.encode(command, sequence: 42)
        let packet = try CommandCodec.decode(data)

        #expect(packet.sequence == 42)
        #expect(packet.command == command)
        #expect(packet.command.flags == [.laser, .fire])
    }

    @Test func crc8MatchesStandardCheckValue() {
        #expect(CommandCodec.crc8("123456789".utf8) == 0xF4)
    }

    @Test func invalidRangesAreRejected() {
        let command = VehicleCommand(
            leftMotor: 100,
            rightMotor: 0,
            turretX: 0,
            turretY: 0,
            flags: []
        )

        #expect(throws: CommandCodecError.outOfRange) {
            try CommandCodec.encode(command, sequence: 0)
        }
    }

    @Test func invalidLengthHeaderAndChecksumAreRejected() throws {
        #expect(throws: CommandCodecError.invalidLength) {
            try CommandCodec.decode(Data(repeating: 0, count: 9))
        }

        #expect(throws: CommandCodecError.invalidHeader) {
            try CommandCodec.decode(Data(repeating: 0, count: CommandCodec.packetSize))
        }

        var corrupted = try CommandCodec.encode(.neutral, sequence: 10)
        corrupted[4] ^= 0x01
        #expect(throws: CommandCodecError.checksumMismatch) {
            try CommandCodec.decode(corrupted)
        }
    }
}

struct LatestWriteQueueTests {
    @Test func onlyNewestPendingWriteIsKept() throws {
        let queue = LatestWriteQueue()
        let first = PendingTransportWrite(data: Data([1]), completion: nil)
        let second = PendingTransportWrite(data: Data([2]), completion: nil)

        #expect(queue.replace(with: first) == nil)
        let replaced = try #require(queue.replace(with: second))

        #expect(replaced.data == first.data)
        #expect(queue.takeLatest()?.data == second.data)
        #expect(queue.isEmpty)
    }
}

struct ControlMathTests {
    @Test func sensitivityPreservesCenterAndEndpoints() {
        #expect(ControlMath.applySensitivity(to: 0, sensitivity: 0) == 0)
        #expect(ControlMath.applySensitivity(to: 1, sensitivity: 0) == 1)
        #expect(ControlMath.applySensitivity(to: -1, sensitivity: 100) == -1)
        #expect(abs(ControlMath.applySensitivity(to: 0.25, sensitivity: 50) - 0.25) < 0.0001)
        #expect(ControlMath.applySensitivity(to: 0.25, sensitivity: 0) < 0.25)
        #expect(ControlMath.applySensitivity(to: 0.25, sensitivity: 100) > 0.25)
    }

    @Test func movementMixesDirectMotorSpeeds() {
        #expect(ControlMath.movementOutput(x: 0, y: 1, sensitivity: 50) == MotorOutput(left: 99, right: 99))
        #expect(ControlMath.movementOutput(x: 1, y: 0, sensitivity: 50) == MotorOutput(left: 99, right: -99))
        #expect(ControlMath.movementOutput(x: 0, y: -1, sensitivity: 50) == MotorOutput(left: -99, right: -99))

        let diagonal = ControlMath.movementOutput(x: 1, y: 1, sensitivity: 50)
        #expect(VehicleCommand.motorRange.contains(diagonal.left))
        #expect(VehicleCommand.motorRange.contains(diagonal.right))
    }

    @Test func turretUsesRelativeStartAndKeepsFullTravel() {
        #expect(ControlMath.turretTarget(start: 80, input: 0, sensitivity: 50) == 80)
        #expect(ControlMath.turretTarget(start: 80, input: 1, sensitivity: 50) == 254)
        #expect(ControlMath.turretTarget(start: 80, input: -1, sensitivity: 50) == -254)

        let precise = ControlMath.turretTarget(start: 0, input: 0.25, sensitivity: 0)
        let linear = ControlMath.turretTarget(start: 0, input: 0.25, sensitivity: 50)
        #expect(precise < linear)
    }

    @Test func zeroTurretSensitivityRequiresHalfTravelForSmallAdjustment() {
        #expect(ControlMath.turretTarget(start: 0, input: 0.5, sensitivity: 0) == 15)
        #expect(ControlMath.turretTarget(start: 0, input: -0.5, sensitivity: 0) == -15)
        #expect(ControlMath.turretTarget(start: 0, input: 0.5, sensitivity: 50) > 15)
    }
}

struct WiFiSessionEngineTests {
    @Test func fakeUDPCompletesHandshakeAndSendsHeartbeat() {
        var engine = WiFiSessionEngine()
        var udp = FakeUDPSink()

        udp.apply(engine.start(at: 0))
        udp.apply(engine.poll(at: 0.25))
        udp.apply(engine.receive("READY,2\n", at: 0.5))
        udp.apply(engine.poll(at: 1.49))
        udp.apply(engine.poll(at: 1.5))
        udp.apply(engine.receive("PONG\n", at: 1.6))

        #expect(udp.messages == ["HELLO,2\n", "HELLO,2\n", "PING\n"])
        #expect(udp.connectedCount == 1)
        #expect(udp.failures.isEmpty)
        #expect(engine.isConnected)
    }

    @Test func fakeUDPRejectsInvalidReadyAndEnforcesHandshakeTimeout() {
        var engine = WiFiSessionEngine()
        var udp = FakeUDPSink()

        udp.apply(engine.start(at: 0))
        udp.apply(engine.receive("READY,1\n", at: 1))
        udp.apply(engine.poll(at: 2.99))
        udp.apply(engine.poll(at: 3.0))

        #expect(udp.connectedCount == 0)
        #expect(udp.failures == [.handshakeTimeout])
        #expect(!engine.isConnected)
    }

    @Test func fakeUDPEnforcesHeartbeatTimeoutAtTwoAndHalfSeconds() {
        var engine = WiFiSessionEngine()
        var udp = FakeUDPSink()

        udp.apply(engine.start(at: 0))
        udp.apply(engine.receive("READY,2\n", at: 0.1))
        udp.apply(engine.poll(at: 2.59))
        #expect(udp.failures.isEmpty)

        udp.apply(engine.poll(at: 2.6))
        #expect(udp.failures == [.heartbeatTimeout])
        #expect(!engine.isConnected)
    }
}

@MainActor
struct ConnectionCoordinatorTests {
    @Test func fakeBluetoothConnectionStateIsForwardedAndLossStopsOutputs() async throws {
        let suiteName = "ConnectionCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let bluetooth = MockTransport(state: .disconnected)
        let coordinator = ConnectionCoordinator(
            bluetoothTransport: bluetooth,
            wifiTransport: MockTransport(state: .disconnected),
            defaults: defaults,
            startsSendTimer: false
        )

        bluetooth.setState(.connecting)
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(coordinator.connectionState == .connecting)

        bluetooth.setState(.connected)
        try await Task.sleep(nanoseconds: 10_000_000)
        coordinator.updateCommand(VehicleCommand(
            leftMotor: 40,
            rightMotor: 35,
            turretX: 75,
            turretY: -20,
            flags: [.laser]
        ))

        bluetooth.setState(.failed("link lost"))
        try await Task.sleep(nanoseconds: 10_000_000)

        #expect(coordinator.connectionState == .failed("link lost"))
        #expect(coordinator.currentCommand == VehicleCommand(
            leftMotor: 0,
            rightMotor: 0,
            turretX: 75,
            turretY: -20,
            flags: []
        ))
    }

    @Test func changingModeSendsSafeStopBeforeDisconnect() async throws {
        let suiteName = "ConnectionCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let bluetooth = MockTransport(state: .connected)
        let wifi = MockTransport(state: .disconnected)
        let coordinator = ConnectionCoordinator(
            bluetoothTransport: bluetooth,
            wifiTransport: wifi,
            defaults: defaults,
            startsSendTimer: false,
            disconnectDelay: 0
        )
        coordinator.updateCommand(VehicleCommand(
            leftMotor: 80,
            rightMotor: 70,
            turretX: 120,
            turretY: -45,
            flags: [.laser, .fire, .trigger]
        ))

        coordinator.selectMode(.wifi)
        try await Task.sleep(nanoseconds: 20_000_000)

        let sentData = try #require(bluetooth.sentData.last)
        let safeCommand = try CommandCodec.decode(sentData).command
        #expect(safeCommand.leftMotor == 0)
        #expect(safeCommand.rightMotor == 0)
        #expect(safeCommand.turretX == 120)
        #expect(safeCommand.turretY == -45)
        #expect(safeCommand.flags.isEmpty)
        #expect(bluetooth.disconnectCount == 1)
        #expect(bluetooth.events.count == 2)
        #expect(bluetooth.events.last == .disconnect)
        #expect(coordinator.selectedMode == .wifi)
        #expect(coordinator.currentCommand == safeCommand)
    }

    @Test func explicitDisconnectSendsSafeStopBeforeDisconnect() async throws {
        let suiteName = "ConnectionCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let bluetooth = MockTransport(state: .connected)
        let coordinator = ConnectionCoordinator(
            bluetoothTransport: bluetooth,
            wifiTransport: MockTransport(state: .disconnected),
            defaults: defaults,
            startsSendTimer: false,
            disconnectDelay: 0
        )
        coordinator.updateCommand(VehicleCommand(
            leftMotor: -60,
            rightMotor: 45,
            turretX: -120,
            turretY: 210,
            flags: [.laser, .fire]
        ))

        coordinator.disconnectSelectedTransport()
        try await Task.sleep(nanoseconds: 20_000_000)

        let sentData = try #require(bluetooth.sentData.last)
        #expect(try CommandCodec.decode(sentData).command == VehicleCommand(
            leftMotor: 0,
            rightMotor: 0,
            turretX: -120,
            turretY: 210,
            flags: []
        ))
        #expect(bluetooth.events.count == 2)
        #expect(bluetooth.events.last == .disconnect)
    }

    @Test func packetsUseIncrementingSequenceAndTwentyFiveMillisecondCadence() throws {
        let suiteName = "ConnectionCoordinatorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let bluetooth = MockTransport(state: .connected)
        let coordinator = ConnectionCoordinator(
            bluetoothTransport: bluetooth,
            wifiTransport: MockTransport(state: .disconnected),
            defaults: defaults,
            startsSendTimer: false
        )

        coordinator.sendCurrentCommand()
        coordinator.sendCurrentCommand()

        #expect(ConnectionCoordinator.sendInterval == 0.025)
        #expect(try CommandCodec.decode(bluetooth.sentData[0]).sequence == 0)
        #expect(try CommandCodec.decode(bluetooth.sentData[1]).sequence == 1)
    }
}

private enum MockTransportEvent: Equatable {
    case send(Data)
    case disconnect
}

private final class MockTransport: VehicleTransport {
    private(set) var connectionState: VehicleConnectionState
    var stateDidChange: ((VehicleConnectionState) -> Void)?
    private(set) var sentData: [Data] = []
    private(set) var disconnectCount = 0
    private(set) var events: [MockTransportEvent] = []

    init(state: VehicleConnectionState) {
        connectionState = state
    }

    func send(_ data: Data, completion: (() -> Void)?) {
        sentData.append(data)
        events.append(.send(data))
        completion?()
    }

    func disconnect() {
        disconnectCount += 1
        events.append(.disconnect)
        connectionState = .disconnected
        stateDidChange?(.disconnected)
    }

    func setState(_ state: VehicleConnectionState) {
        connectionState = state
        stateDidChange?(state)
    }
}

private struct FakeUDPSink {
    private(set) var messages: [String] = []
    private(set) var connectedCount = 0
    private(set) var failures: [WiFiSessionFailure] = []

    mutating func apply(_ actions: [WiFiSessionAction]) {
        for action in actions {
            switch action {
            case .sendHello:
                messages.append("HELLO,2\n")
            case .sendPing:
                messages.append("PING\n")
            case .connected:
                connectedCount += 1
            case .failed(let failure):
                failures.append(failure)
            }
        }
    }
}
