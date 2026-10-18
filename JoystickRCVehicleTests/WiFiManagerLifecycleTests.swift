import Foundation
import NetworkExtension
import Testing
@testable import JoystickRCVehicle

@MainActor
struct WiFiManagerLifecycleTests {
    @Test func cancelledHotspotSuccessAndFailureCannotStartUDPOrPublishState() async throws {
        let outcomes: [Error?] = [nil, WiFiTestError.late]
        for error in outcomes {
            let fixture = try WiFiFixture()
            fixture.manager.connect()
            #expect(fixture.manager.connectionSessionID != nil)
            fixture.manager.disconnect()
            #expect(fixture.manager.connectionSessionID == nil)

            fixture.hotspot.complete(0, error: error)
            await fixture.flush()

            #expect(fixture.createdConnections.isEmpty)
            #expect(fixture.manager.connectionState == .disconnected)
        }
    }

    @Test func newerHotspotAttemptWinsRegardlessOfOldCompletionOrder() async throws {
        let outcomes: [Error?] = [nil, WiFiTestError.late]
        for oldError in outcomes {
            for oldCompletesFirst in [true, false] {
                let fixture = try WiFiFixture()
                fixture.manager.connect()
                let firstID = fixture.manager.connectionSessionID
                fixture.manager.host = "192.168.4.2"
                fixture.manager.connect()
                let secondID = fixture.manager.connectionSessionID
                #expect(firstID != secondID)

                if oldCompletesFirst { fixture.hotspot.complete(0, error: oldError) }
                fixture.hotspot.complete(1)
                if !oldCompletesFirst { fixture.hotspot.complete(0, error: oldError) }
                await fixture.flush()

                #expect(fixture.createdConnections.map(\.host) == ["192.168.4.2"])
                #expect(fixture.manager.connectionState == .connecting)
                #expect(fixture.manager.connectionSessionID == secondID)
            }
        }
    }

    @Test func pendingJoinUsesOneConfigurationSnapshotAndDisconnectRemovesItsSSID() async throws {
        let fixture = try WiFiFixture()
        fixture.manager.ssid = "Tank-A"
        fixture.manager.host = "192.168.4.1"
        fixture.manager.portText = "4210"
        fixture.manager.connect()
        fixture.manager.ssid = "Tank-B"
        fixture.manager.host = "192.168.9.9"
        fixture.manager.portText = "9999"

        fixture.hotspot.complete(0)
        await fixture.flush()
        let created = try #require(fixture.createdConnections.first)
        #expect(created.host == "192.168.4.1")
        #expect(created.port == 4210)
        #expect(fixture.hotspot.configurations.first?.ssid == "Tank-A")

        fixture.manager.disconnect()
        #expect(fixture.hotspot.removedSSIDs == ["Tank-A"])
    }

    @Test func disconnectAfterJoinFailureStillRemovesOriginalConfiguration() async throws {
        let fixture = try WiFiFixture()
        fixture.manager.ssid = "Tank-A"
        fixture.manager.connect()
        fixture.hotspot.complete(0, error: WiFiTestError.late)
        await fixture.flush()
        fixture.manager.ssid = "Tank-B"
        fixture.manager.disconnect()
        #expect(fixture.hotspot.removedSSIDs == ["Tank-A"])
    }

    @Test func changingSSIDRemovesSupersededConfiguration() async throws {
        let fixture = try WiFiFixture()
        fixture.manager.ssid = "Tank-A"
        fixture.manager.connect()
        fixture.manager.ssid = "Tank-B"
        fixture.manager.connect()
        #expect(fixture.hotspot.removedSSIDs == ["Tank-A"])
        fixture.manager.disconnect()
        #expect(fixture.hotspot.removedSSIDs == ["Tank-A", "Tank-B"])
    }

    @Test func alreadyAssociatedStillStartsCurrentAttempt() async throws {
        let fixture = try WiFiFixture()
        fixture.manager.connect()
        fixture.hotspot.complete(0, error: NSError(
            domain: NEHotspotConfigurationErrorDomain,
            code: NEHotspotConfigurationError.alreadyAssociated.rawValue
        ))
        await fixture.flush()
        #expect(fixture.createdConnections.count == 1)
        #expect(fixture.manager.connectionState == .connecting)
    }

    @Test func invalidReconnectAlsoRevokesPendingJoin() async throws {
        let fixture = try WiFiFixture()
        fixture.manager.connect()
        fixture.manager.portText = "0"
        fixture.manager.connect()
        let invalidState = fixture.manager.connectionState
        #expect(fixture.manager.connectionSessionID == nil)

        fixture.hotspot.complete(0)
        await fixture.flush()
        #expect(fixture.createdConnections.isEmpty)
        #expect(fixture.manager.connectionState == invalidState)
        if case .failed = invalidState {} else { Issue.record("Invalid configuration must fail") }
    }

    @Test func oldReceiveErrorAndReadyDoNotAffectReplacementOrAddReceivers() async throws {
        let oldMessages: [String?] = [nil, "READY,2\n"]
        for oldMessage in oldMessages {
            let fixture = try WiFiFixture()
            let old = try await fixture.startReadyConnection()
            let oldReceive = try #require(fixture.onNetwork { old.receives.first })
            let replacement = try await fixture.startReadyConnection()
            let replacementID = fixture.manager.connectionSessionID

            oldReceive(oldMessage.map { Data($0.utf8) }, oldMessage == nil ? WiFiTestError.late : nil)
            await fixture.flush()

            #expect(fixture.manager.connectionState == .connecting)
            #expect(fixture.manager.connectionSessionID == replacementID)
            #expect(fixture.onNetwork { replacement.receiveCount } == 1)
            #expect(!fixture.onNetwork { replacement.cancelled })
            #expect(fixture.onNetwork { old.cancelled })
        }
    }

    @Test func oldPongDoesNotExtendReplacementHeartbeatDeadline() async throws {
        let fixture = try WiFiFixture()
        let old = try await fixture.startConnectedConnection()
        let oldReceive = try #require(fixture.onNetwork { old.receives.first })
        let replacement = try await fixture.startConnectedConnection()
        #expect(fixture.manager.connectionState == .connected)

        fixture.onNetwork { fixture.clock.time = 2.4 }
        oldReceive(Data("PONG\n".utf8), nil)
        await fixture.flush()
        #expect(fixture.onNetwork { replacement.receiveCount } == 2)

        fixture.onNetwork {
            fixture.clock.time = 2.5
            fixture.timers.last?.fire()
        }
        await fixture.flush()
        #expect(fixture.onNetwork { replacement.cancelled })
        #expect(fixture.manager.connectionSessionID == nil)
        if case .failed = fixture.manager.connectionState {} else { Issue.record("Heartbeat must time out") }
    }

    @Test func staleStateHandlerAndCancelledTimerCannotAffectReplacement() async throws {
        let fixture = try WiFiFixture()
        let old = try await fixture.startReadyConnection()
        let oldState = try #require(fixture.onNetwork { old.stateUpdateHandler })
        let oldTimer = try #require(fixture.onNetwork { fixture.timers.first })
        let replacement = try await fixture.startReadyConnection()

        fixture.onNetwork { fixture.clock.time = 10 }
        oldState(.failed(WiFiTestError.late))
        oldState(.ready)
        oldTimer.fire() // Deliberately deliver a callback after cancellation.
        await fixture.flush()

        #expect(fixture.manager.connectionState == .connecting)
        #expect(fixture.onNetwork { replacement.receiveCount } == 1)
        #expect(fixture.onNetwork { replacement.sentData } == [Data("HELLO,2\n".utf8)])
        #expect(!fixture.onNetwork { replacement.cancelled })
        #expect(oldTimer.cancelled)
    }

    @Test func queuedConnectedPublicationCannotUndoSynchronousDisconnect() async throws {
        let fixture = try WiFiFixture()
        let connection = try await fixture.startReadyConnection()
        // Keep main occupied until the network callback has queued .connected.
        fixture.onNetwork { connection.deliver("READY,2\n") }
        fixture.onNetwork {}
        fixture.manager.disconnect()
        await fixture.flush()
        #expect(fixture.manager.connectionState == .disconnected)
        #expect(fixture.manager.connectionSessionID == nil)
    }

    @Test func queuedFailurePublicationCannotOverwriteNewAttempt() async throws {
        let fixture = try WiFiFixture()
        let old = try await fixture.startReadyConnection()
        fixture.onNetwork { old.deliver(error: WiFiTestError.late) }
        fixture.onNetwork {}
        fixture.manager.connect()
        await fixture.flush()
        #expect(fixture.manager.connectionState == .connecting)
        #expect(fixture.manager.connectionSessionID != nil)
    }

    @Test func cancelledWriteCompletesOnceAndLateCompletionCannotDrainReplacementQueue() async throws {
        let outcomes: [Error?] = [nil, WiFiTestError.late]
        for error in outcomes {
            let fixture = try WiFiFixture()
            let old = try await fixture.startConnectedConnection()
            var oldResults: [TransportWriteResult] = []
            fixture.manager.sendStop(Data([1])) { oldResults.append($0) }
            await fixture.flush()
            let oldCompletion = try #require(fixture.onNetwork { old.sendCompletions.first })

            let replacement = try await fixture.startConnectedConnection()
            fixture.manager.send(Data([2]))
            fixture.manager.send(Data([3]))
            await fixture.flush()
            oldCompletion(error)
            await fixture.flush()

            #expect(oldResults == [.cancelled])
            #expect(fixture.manager.connectionState == .connected)
            #expect(fixture.onNetwork { replacement.sentData } == [Data("HELLO,2\n".utf8), Data([2])])
            #expect(!fixture.onNetwork { replacement.cancelled })
        }
    }

    @Test func currentStopSendErrorReportsFailureAndInvalidatesSession() async throws {
        let fixture = try WiFiFixture()
        let connection = try await fixture.startConnectedConnection()
        var results: [TransportWriteResult] = []
        fixture.manager.sendStop(Data([0])) { results.append($0) }
        await fixture.flush()
        fixture.onNetwork { connection.finishNextSend(error: WiFiTestError.late) }
        await fixture.flush()
        #expect(results == [.failed])
        #expect(fixture.manager.connectionSessionID == nil)
        #expect(fixture.onNetwork { connection.cancelled })
        if case .failed = fixture.manager.connectionState {} else { Issue.record("Send error must fail the session") }
    }

    @Test func stopWaitsForInFlightWriteAndCannotBeReplacedByMovement() async throws {
        let fixture = try WiFiFixture()
        let connection = try await fixture.startConnectedConnection()
        var stopResults: [TransportWriteResult] = []
        fixture.manager.send(Data([1]))
        fixture.manager.sendStop(Data([0])) { stopResults.append($0) }
        fixture.manager.send(Data([9]))
        await fixture.flush()
        #expect(fixture.onNetwork { connection.sentData } == [Data("HELLO,2\n".utf8), Data([1])])
        #expect(stopResults.isEmpty)

        fixture.onNetwork { connection.finishNextSend() }
        await fixture.flush()
        #expect(fixture.onNetwork { connection.sentData.last } == Data([0]))
        #expect(stopResults.isEmpty)

        fixture.onNetwork { connection.finishNextSend() }
        await fixture.flush()
        #expect(stopResults == [.submitted])
        #expect(!fixture.onNetwork { connection.sentData.contains(Data([9])) })
    }

    @Test func pendingStopIsCancelledRatherThanReportedAsSubmitted() async throws {
        let fixture = try WiFiFixture()
        _ = try await fixture.startConnectedConnection()
        var results: [TransportWriteResult] = []
        fixture.manager.send(Data([1]))
        fixture.manager.sendStop(Data([0])) { results.append($0) }
        await fixture.flush()
        fixture.manager.disconnect()
        await fixture.flush()
        #expect(results == [.cancelled])
    }

    @Test func currentReceiveMaintainsOneLoopAndCurrentPongKeepsHeartbeatAlive() async throws {
        let fixture = try WiFiFixture()
        let connection = try await fixture.startConnectedConnection()
        fixture.onNetwork {
            fixture.clock.time = 2.4
            connection.deliver("PONG\n")
        }
        await fixture.flush()
        fixture.onNetwork {
            fixture.clock.time = 2.5
            fixture.timers.last?.fire()
        }
        await fixture.flush()

        #expect(fixture.manager.connectionState == .connected)
        #expect(fixture.onNetwork { connection.receives.count } == 1)
        #expect(fixture.onNetwork { connection.sentData.last } == Data("PING\n".utf8))
    }
}

private enum WiFiTestError: Error { case late }

private final class FakeWiFiHotspot: WiFiHotspotJoining {
    private(set) var configurations: [WiFiConnectionConfiguration] = []
    private(set) var removedSSIDs: [String] = []
    private var completions: [(Error?) -> Void] = []

    func apply(_ configuration: WiFiConnectionConfiguration, completion: @escaping (Error?) -> Void) {
        configurations.append(configuration)
        completions.append(completion)
    }

    func removeConfiguration(forSSID ssid: String) { removedSSIDs.append(ssid) }
    func complete(_ index: Int, error: Error? = nil) { completions[index](error) }
}

private final class FakeWiFiConnection: WiFiUDPConnection {
    var stateUpdateHandler: ((WiFiUDPState) -> Void)?
    var receives: [(Data?, Error?) -> Void] = []
    var sendCompletions: [(Error?) -> Void] = []
    private(set) var receiveCount = 0
    private(set) var sentData: [Data] = []
    private(set) var cancelled = false

    func start(queue: DispatchQueue) {}
    func cancel() { cancelled = true }

    func receiveMessage(completion: @escaping (Data?, Error?) -> Void) {
        receiveCount += 1
        receives.append(completion)
    }

    func send(_ data: Data, completion: ((Error?) -> Void)?) {
        sentData.append(data)
        if let completion { sendCompletions.append(completion) }
    }

    func deliver(_ message: String? = nil, error: Error? = nil) {
        let receive = receives.removeFirst()
        receive(message.map { Data($0.utf8) }, error)
    }

    func finishNextSend(error: Error? = nil) { sendCompletions.removeFirst()(error) }
}

private final class FakeWiFiTimer: WiFiPollTimer {
    private let handler: () -> Void
    private(set) var cancelled = false
    init(handler: @escaping () -> Void) { self.handler = handler }
    func cancel() { cancelled = true }
    func fire() { handler() }
}

private final class FakeWiFiClock { var time: TimeInterval = 0 }

@MainActor
private final class WiFiFixture {
    struct CreatedConnection {
        let host: String
        let port: UInt16
        let connection: FakeWiFiConnection
    }

    let manager: WiFiManager
    let hotspot: FakeWiFiHotspot
    let clock: FakeWiFiClock
    let networkQueue: DispatchQueue
    private let defaults: UserDefaults
    private let suiteName: String
    private let resources: Resources

    // Written/read only on networkQueue. The synchronous accessor is also used
    // by tests to make every race ordering deterministic, without sleeps.
    private final class Resources {
        var connections: [CreatedConnection] = []
        var timers: [FakeWiFiTimer] = []
    }
    var createdConnections: [CreatedConnection] { onNetwork { resources.connections } }
    var timers: [FakeWiFiTimer] { resources.timers }

    init() throws {
        let suiteName = "WiFiManagerLifecycleTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let resources = Resources()
        let clock = FakeWiFiClock()
        let hotspot = FakeWiFiHotspot()
        let networkQueue = DispatchQueue(label: suiteName)
        self.suiteName = suiteName
        self.defaults = defaults
        self.resources = resources
        self.clock = clock
        self.hotspot = hotspot
        self.networkQueue = networkQueue
        manager = WiFiManager(
            defaults: defaults,
            hotspot: hotspot,
            makeConnection: { host, port in
                let connection = FakeWiFiConnection()
                resources.connections.append(CreatedConnection(host: host, port: port, connection: connection))
                return connection
            },
            makeTimer: { _, handler in
                let timer = FakeWiFiTimer(handler: handler)
                resources.timers.append(timer)
                return timer
            },
            networkQueue: networkQueue,
            now: { clock.time }
        )
    }

    deinit { defaults.removePersistentDomain(forName: suiteName) }

    func onNetwork<T>(_ body: () -> T) -> T { networkQueue.sync(execute: body) }

    func flush() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            networkQueue.async {
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    func startReadyConnection() async throws -> FakeWiFiConnection {
        manager.connect()
        hotspot.complete(hotspot.configurations.count - 1)
        await flush()
        let connection = try #require(createdConnections.last?.connection)
        onNetwork { connection.stateUpdateHandler?(.ready) }
        await flush()
        return connection
    }

    func startConnectedConnection() async throws -> FakeWiFiConnection {
        let connection = try await startReadyConnection()
        onNetwork { connection.deliver("READY,2\n") }
        await flush()
        return connection
    }
}
