import Foundation

enum ConnectionMode: String, CaseIterable, Identifiable {
    case bluetooth
    case wifi

    var id: String { rawValue }
}

enum VehicleConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)

    var isConnected: Bool {
        self == .connected
    }
}

struct DeviceFlags: OptionSet, Equatable, Sendable {
    let rawValue: Int

    static let laser = DeviceFlags(rawValue: 1 << 0)
    static let fire = DeviceFlags(rawValue: 1 << 1)
    static let trigger = DeviceFlags(rawValue: 1 << 2)
    static let all: DeviceFlags = [.laser, .fire, .trigger]
}

struct VehicleCommand: Equatable, Sendable {
    static let motorRange = -99...99
    static let turretRange = -254...254

    var leftMotor: Int
    var rightMotor: Int
    var turretX: Int
    var turretY: Int
    var flags: DeviceFlags

    static let neutral = VehicleCommand(
        leftMotor: 0,
        rightMotor: 0,
        turretX: 0,
        turretY: 0,
        flags: []
    )

    func safelyStopped() -> VehicleCommand {
        VehicleCommand(
            leftMotor: 0,
            rightMotor: 0,
            turretX: turretX,
            turretY: turretY,
            flags: []
        )
    }
}

struct VehicleCommandPacket: Equatable, Sendable {
    let sequence: UInt8
    let command: VehicleCommand
}

enum CommandCodecError: Error, Equatable {
    case invalidLength
    case invalidHeader
    case checksumMismatch
    case outOfRange
}

enum CommandCodec {
    static let header: UInt8 = 0xA2
    static let packetSize = 10
    static let crcPolynomial: UInt8 = 0x07

    static func validate(_ command: VehicleCommand) throws {
        guard VehicleCommand.motorRange.contains(command.leftMotor),
              VehicleCommand.motorRange.contains(command.rightMotor),
              VehicleCommand.turretRange.contains(command.turretX),
              VehicleCommand.turretRange.contains(command.turretY),
              command.flags.rawValue >= 0,
              command.flags.rawValue <= DeviceFlags.all.rawValue else {
            throw CommandCodecError.outOfRange
        }
    }

    static func encode(_ command: VehicleCommand, sequence: UInt8) throws -> Data {
        try validate(command)

        var bytes: [UInt8] = [
            header,
            sequence,
            UInt8(bitPattern: Int8(command.leftMotor)),
            UInt8(bitPattern: Int8(command.rightMotor))
        ]
        appendLittleEndian(command.turretX, to: &bytes)
        appendLittleEndian(command.turretY, to: &bytes)
        bytes.append(UInt8(command.flags.rawValue))
        bytes.append(crc8(bytes))
        return Data(bytes)
    }

    static func decode(_ data: Data) throws -> VehicleCommandPacket {
        guard data.count == packetSize else {
            throw CommandCodecError.invalidLength
        }
        let bytes = [UInt8](data)
        guard bytes[0] == header else {
            throw CommandCodecError.invalidHeader
        }
        guard crc8(bytes.dropLast()) == bytes[packetSize - 1] else {
            throw CommandCodecError.checksumMismatch
        }

        let command = VehicleCommand(
            leftMotor: Int(Int8(bitPattern: bytes[2])),
            rightMotor: Int(Int8(bitPattern: bytes[3])),
            turretX: signedLittleEndian(low: bytes[4], high: bytes[5]),
            turretY: signedLittleEndian(low: bytes[6], high: bytes[7]),
            flags: DeviceFlags(rawValue: Int(bytes[8]))
        )
        try validate(command)
        return VehicleCommandPacket(sequence: bytes[1], command: command)
    }

    static func crc8<S: Sequence>(_ bytes: S) -> UInt8 where S.Element == UInt8 {
        var crc: UInt8 = 0
        for byte in bytes {
            crc ^= byte
            for _ in 0..<8 {
                crc = (crc & 0x80) == 0
                    ? crc << 1
                    : (crc << 1) ^ crcPolynomial
            }
        }
        return crc
    }

    private static func appendLittleEndian(_ value: Int, to bytes: inout [UInt8]) {
        let rawValue = UInt16(bitPattern: Int16(value))
        bytes.append(UInt8(truncatingIfNeeded: rawValue))
        bytes.append(UInt8(truncatingIfNeeded: rawValue >> 8))
    }

    private static func signedLittleEndian(low: UInt8, high: UInt8) -> Int {
        let rawValue = UInt16(low) | (UInt16(high) << 8)
        return Int(Int16(bitPattern: rawValue))
    }
}
