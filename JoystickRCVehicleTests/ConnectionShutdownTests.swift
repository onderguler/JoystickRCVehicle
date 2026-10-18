import Foundation
import Testing
@testable import JoystickRCVehicle

@MainActor
struct ConnectionShutdownTests {
    @Test func backpressureWaitsForSubmissionThenAllowsADrainGrace() throws {
        let fixture = try ShutdownFixture()
        defer { fixture.cleanUp() }
        fixture.coordinator.updateCommand(VehicleCommand(leftMotor: 90, rightMotor: -60, turretX: 123, turretY: -45, flags: .all))
        fixture.coordinator.disconnectSelectedTransport()

        // Repeated 25 ms command ticks must not replace the queued safe stop.
        for _ in 0..<4 {
            fixture.scheduler.advance(by: 0.025)
            fixture.coordinator.updateCommand(.neutral)
            fixture.coordinator.sendCurrentCommand()
        }
        #expect(fixture.bluetooth.disconnectCount == 0)
        #expect(fixture.bluetooth.ordinaryWrites.isEmpty)
        #expect(fixture.bluetooth.stopWrites.count == 1)
        let stopData = try #require(fixture.bluetooth.stopWrites.first)
        let stop = try CommandCodec.decode(stopData).command
        #expect(stop == VehicleCommand(leftMotor: 0, rightMotor: 0, turretX: 123, turretY: -45, flags: []))

        fixture.bluetooth.completeStop(.submitted)
        #expect(fixture.bluetooth.disconnectCount == 0)
        fixture.scheduler.advance(by: 0.059)
        #expect(fixture.bluetooth.disconnectCount == 0)
        fixture.scheduler.advance(by: 0.002)
        #expect(fixture.bluetooth.disconnectCount == 1)
        fixture.scheduler.advance(by: 1)
        #expect(fixture.bluetooth.disconnectCount == 1)
    }

    @Test func responseStopWaitsThroughBackpressureThenDisconnectsOnceOnAcknowledgement() throws {
        let fixture = try ShutdownFixture()
        defer { fixture.cleanUp() }
        fixture.coordinator.disconnectSelectedTransport()

        // The preceding response write occupies the BLE slot for 100 ms.
        // Neither timer ticks nor fresh movement input can replace the stop.
        for _ in 0..<4 {
            fixture.scheduler.advance(by: 0.025)
            fixture.coordinator.updateCommand(VehicleCommand(
                leftMotor: 99, rightMotor: -99, turretX: 12, turretY: -34, flags: .all
            ))
            fixture.coordinator.sendCurrentCommand()
            #expect(fixture.bluetooth.disconnectCount == 0)
        }
        #expect(fixture.bluetooth.stopWrites.count == 1)
        #expect(fixture.bluetooth.ordinaryWrites.isEmpty)
        #expect(fixture.coordinator.currentCommand.leftMotor == 0)
        #expect(fixture.coordinator.currentCommand.rightMotor == 0)
        #expect(fixture.coordinator.currentCommand.flags.isEmpty)

        fixture.bluetooth.completeStop(.acknowledged)
        #expect(fixture.bluetooth.disconnectCount == 1)
        fixture.scheduler.advance(by: 1)
        #expect(fixture.bluetooth.disconnectCount == 1)
        fixture.bluetooth.completeStop(.acknowledged)
        #expect(fixture.bluetooth.disconnectCount == 1)
    }

    @Test func acknowledgementFinishesWithoutWaitingForWatchdog() throws {
        let fixture = try ShutdownFixture()
        defer { fixture.cleanUp() }
        fixture.coordinator.disconnectSelectedTransport()
        fixture.bluetooth.completeStop(.acknowledged)
        #expect(fixture.bluetooth.disconnectCount == 1)
        fixture.scheduler.advance(by: 1)
        #expect(fixture.bluetooth.disconnectCount == 1)
    }

    @Test func neverWritableLinkHasABoundedWatchdogFallback() throws {
        let fixture = try ShutdownFixture()
        defer { fixture.cleanUp() }
        fixture.coordinator.disconnectSelectedTransport()
        fixture.scheduler.advance(by: 0.499)
        #expect(fixture.bluetooth.disconnectCount == 0)
        fixture.scheduler.advance(by: 0.002)
        #expect(fixture.bluetooth.disconnectCount == 1)
        fixture.bluetooth.completeStop(.submitted)
        fixture.scheduler.advance(by: 1)
        #expect(fixture.bluetooth.disconnectCount == 1)
    }

    @Test func cancellationOrReplacementIsNotMistakenForSubmission() throws {
        for result in [TransportWriteResult.cancelled, .superseded, .failed] {
            let fixture = try ShutdownFixture()
            defer { fixture.cleanUp() }
            fixture.coordinator.disconnectSelectedTransport()
            fixture.bluetooth.completeStop(result)
            fixture.scheduler.advance(by: 0.1)
            #expect(fixture.bluetooth.disconnectCount == 0)
            fixture.scheduler.advance(by: 0.5)
            #expect(fixture.bluetooth.disconnectCount == 1)
        }
    }

    @Test func repeatedDisconnectDoesNotReplaceThePendingStop() throws {
        let fixture = try ShutdownFixture()
        defer { fixture.cleanUp() }
        fixture.coordinator.disconnectSelectedTransport()
        fixture.coordinator.disconnectSelectedTransport()
        fixture.coordinator.updateCommand(VehicleCommand(leftMotor: 99, rightMotor: 99, turretX: 50, turretY: -50, flags: .all))
        fixture.coordinator.sendCurrentCommand()
        #expect(fixture.bluetooth.stopWrites.count == 1)
        #expect(fixture.bluetooth.ordinaryWrites.isEmpty)
        #expect(fixture.coordinator.currentCommand.leftMotor == 0)
        #expect(fixture.coordinator.currentCommand.flags.isEmpty)
    }

    @Test func staleCompletionAndDrainTimerCannotDisconnectANewSession() throws {
        let fixture = try ShutdownFixture()
        defer { fixture.cleanUp() }
        fixture.coordinator.disconnectSelectedTransport()
        let oldCompletion = try #require(fixture.bluetooth.stopCompletion)
        oldCompletion(.submitted)
        fixture.bluetooth.reconnect()
        oldCompletion(.acknowledged)
        fixture.scheduler.advance(by: 1)
        #expect(fixture.bluetooth.disconnectCount == 0)
        #expect(fixture.bluetooth.connectionState == .connected)
        fixture.coordinator.sendCurrentCommand()
        #expect(fixture.bluetooth.ordinaryWrites.count == 1)
    }

    @Test func watchdogChecksSessionEvenWithoutAStateNotification() throws {
        let fixture = try ShutdownFixture()
        defer { fixture.cleanUp() }
        fixture.coordinator.disconnectSelectedTransport()
        fixture.bluetooth.reconnect(notify: false)
        fixture.scheduler.advance(by: 1)
        #expect(fixture.bluetooth.disconnectCount == 0)
        #expect(fixture.bluetooth.connectionState == .connected)
    }

    @Test func lateOldStopCannotFinishANewerStopOnSameTransport() throws {
        let fixture = try ShutdownFixture()
        defer { fixture.cleanUp() }
        fixture.coordinator.disconnectSelectedTransport()
        let oldCompletion = try #require(fixture.bluetooth.stopCompletion)
        fixture.bluetooth.reconnect()
        fixture.coordinator.disconnectSelectedTransport()
        oldCompletion(.acknowledged)
        #expect(fixture.bluetooth.disconnectCount == 0)
        #expect(fixture.bluetooth.stopWrites.count == 2)
        fixture.bluetooth.completeStop(.acknowledged)
        #expect(fixture.bluetooth.disconnectCount == 1)
    }

    @Test func rapidModeReturnKeepsOldSessionStoppedUntilItsStopCompletes() throws {
        let fixture = try ShutdownFixture()
        defer { fixture.cleanUp() }
        fixture.coordinator.selectMode(.wifi)
        fixture.coordinator.selectMode(.bluetooth)
        fixture.coordinator.sendCurrentCommand()
        #expect(fixture.bluetooth.stopWrites.count == 1)
        #expect(fixture.bluetooth.ordinaryWrites.isEmpty)
        fixture.bluetooth.completeStop(.acknowledged)
        #expect(fixture.bluetooth.disconnectCount == 1)
        #expect(fixture.coordinator.selectedMode == .bluetooth)
        #expect(fixture.coordinator.connectionState == .disconnected)
    }
}

private struct ShutdownFixture {
    let suiteName: String
    let defaults: UserDefaults
    let bluetooth: ShutdownTransport
    let scheduler: ShutdownScheduler
    let coordinator: ConnectionCoordinator

    init() throws {
        let suiteName = "ConnectionShutdownTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let bluetooth = ShutdownTransport(state: .connected)
        let scheduler = ShutdownScheduler()
        self.suiteName = suiteName
        self.defaults = defaults
        self.bluetooth = bluetooth
        self.scheduler = scheduler
        coordinator = ConnectionCoordinator(
            bluetoothTransport: bluetooth,
            wifiTransport: ShutdownTransport(state: .disconnected),
            defaults: defaults,
            startsSendTimer: false,
            disconnectDelay: 0.5,
            submissionDrainDelay: 0.06,
            scheduleDisconnect: scheduler.schedule
        )
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private final class ShutdownScheduler {
    private var now: TimeInterval = 0
    private var scheduled: [(deadline: TimeInterval, work: DispatchWorkItem)] = []

    func schedule(after delay: TimeInterval, work: DispatchWorkItem) {
        scheduled.append((now + delay, work))
    }

    func advance(by duration: TimeInterval) {
        let target = now + duration
        while let next = scheduled.indices.min(by: { scheduled[$0].deadline < scheduled[$1].deadline }),
              scheduled[next].deadline <= target {
            let item = scheduled.remove(at: next)
            now = item.deadline
            item.work.perform()
        }
        now = target
    }
}

private final class ShutdownTransport: VehicleTransport {
    private(set) var connectionState: VehicleConnectionState
    var stateDidChange: ((VehicleConnectionState) -> Void)?
    private(set) var connectionSessionID: UUID? = UUID()
    private(set) var ordinaryWrites: [Data] = []
    private(set) var stopWrites: [Data] = []
    private(set) var stopCompletion: ((TransportWriteResult) -> Void)?
    private(set) var disconnectCount = 0

    init(state: VehicleConnectionState) {
        connectionState = state
    }

    func send(_ data: Data, completion: (() -> Void)?) {
        ordinaryWrites.append(data)
        completion?()
    }

    func sendStop(_ data: Data, completion: @escaping (TransportWriteResult) -> Void) {
        stopWrites.append(data)
        stopCompletion = completion
    }

    func completeStop(_ result: TransportWriteResult) {
        stopCompletion?(result)
    }

    func disconnect() {
        disconnectCount += 1
        connectionSessionID = nil
        connectionState = .disconnected
        stateDidChange?(.disconnected)
    }

    func reconnect(notify: Bool = true) {
        connectionSessionID = UUID()
        connectionState = .connecting
        if notify { stateDidChange?(.connecting) }
        connectionState = .connected
        if notify { stateDidChange?(.connected) }
    }
}
