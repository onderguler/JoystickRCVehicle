import Foundation

enum WiFiSessionFailure: Equatable {
    case handshakeTimeout
    case heartbeatTimeout
}

enum WiFiSessionAction: Equatable {
    case sendHello
    case sendPing
    case connected
    case failed(WiFiSessionFailure)
}

struct WiFiSessionEngine {
    private enum Phase {
        case idle
        case handshaking(startedAt: TimeInterval)
        case connected(lastPongAt: TimeInterval, lastPingAt: TimeInterval)
    }

    private(set) var isConnected = false
    private var phase: Phase = .idle

    mutating func start(at time: TimeInterval) -> [WiFiSessionAction] {
        isConnected = false
        phase = .handshaking(startedAt: time)
        return [.sendHello]
    }

    mutating func receive(_ message: String, at time: TimeInterval) -> [WiFiSessionAction] {
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)

        switch phase {
        case .handshaking(let startedAt) where message == "READY,2":
            guard time - startedAt < 3.0 else {
                return fail(.handshakeTimeout)
            }
            isConnected = true
            phase = .connected(lastPongAt: time, lastPingAt: time)
            return [.connected]
        case .connected(let lastPongAt, let lastPingAt) where message == "PONG":
            guard time - lastPongAt < 2.5 else {
                return fail(.heartbeatTimeout)
            }
            phase = .connected(lastPongAt: time, lastPingAt: lastPingAt)
            return []
        default:
            return []
        }
    }

    mutating func poll(at time: TimeInterval) -> [WiFiSessionAction] {
        switch phase {
        case .idle:
            return []
        case .handshaking(let startedAt):
            guard time - startedAt < 3.0 else {
                return fail(.handshakeTimeout)
            }
            return [.sendHello]
        case .connected(let lastPongAt, let lastPingAt):
            guard time - lastPongAt < 2.5 else {
                return fail(.heartbeatTimeout)
            }
            guard time - lastPingAt >= 1.0 else { return [] }
            phase = .connected(lastPongAt: lastPongAt, lastPingAt: time)
            return [.sendPing]
        }
    }

    mutating func reset() {
        isConnected = false
        phase = .idle
    }

    private mutating func fail(_ failure: WiFiSessionFailure) -> [WiFiSessionAction] {
        reset()
        return [.failed(failure)]
    }
}
