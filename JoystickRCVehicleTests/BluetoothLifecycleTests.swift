import Foundation
import Testing
@testable import JoystickRCVehicle

struct BluetoothLifecycleTests {
    @Test func oldPeripheralCallbacksCannotChangeANewerSession() {
        let peripheralA = NSObject()
        let peripheralB = NSObject()
        let serviceA = NSObject()
        let serviceB = NSObject()
        let characteristicA = NSObject()
        let characteristicB = NSObject()
        var session = BluetoothSessionIdentity()
        let attemptA = session.begin(peripheral: peripheralA)
        #expect(session.registerServices([serviceA], peripheral: peripheralA, sessionID: attemptA))
        #expect(session.select(characteristic: characteristicA, service: serviceA, peripheral: peripheralA, sessionID: attemptA))

        let attemptB = session.begin(peripheral: peripheralB)
        #expect(!session.acceptsCurrentPeripheral(peripheralA))
        #expect(session.acceptsCurrentPeripheral(peripheralB))
        #expect(!session.accepts(peripheral: peripheralA, sessionID: attemptA))
        #expect(!session.accepts(peripheral: peripheralA, sessionID: attemptB))
        #expect(!session.registerServices([serviceA], peripheral: peripheralA, sessionID: attemptA))
        #expect(!session.select(characteristic: characteristicA, service: serviceA, peripheral: peripheralA, sessionID: attemptA))
        #expect(session.registerServices([serviceB], peripheral: peripheralB, sessionID: attemptB))
        #expect(!session.accepts(service: serviceA, peripheral: peripheralB, sessionID: attemptB))
        #expect(session.select(characteristic: characteristicB, service: serviceB, peripheral: peripheralB, sessionID: attemptB))
        #expect(!session.accepts(characteristic: characteristicA, peripheral: peripheralA, sessionID: attemptA))
        #expect(!session.accepts(characteristic: characteristicA, peripheral: peripheralB, sessionID: attemptB))
        #expect(session.accepts(characteristic: characteristicB, peripheral: peripheralB, sessionID: attemptB))
        #expect(session.id == attemptB)
    }

    @Test func reconnectingSamePeripheralStillRejectsOldDelegateToken() {
        let peripheral = NSObject()
        let service = NSObject()
        let characteristic = NSObject()
        var session = BluetoothSessionIdentity()
        let oldAttempt = session.begin(peripheral: peripheral)
        _ = session.registerServices([service], peripheral: peripheral, sessionID: oldAttempt)
        _ = session.select(characteristic: characteristic, service: service, peripheral: peripheral, sessionID: oldAttempt)
        session.invalidate()
        let newAttempt = session.begin(peripheral: peripheral)

        #expect(newAttempt != oldAttempt)
        #expect(!session.accepts(peripheral: peripheral, sessionID: oldAttempt))
        #expect(!session.accepts(service: service, peripheral: peripheral, sessionID: newAttempt))
        #expect(!session.accepts(characteristic: characteristic, peripheral: peripheral, sessionID: newAttempt))
        #expect(session.accepts(peripheral: peripheral, sessionID: newAttempt))
    }

    @Test func invalidatedSessionRejectsAllLateCallbacks() {
        let peripheral = NSObject()
        let service = NSObject()
        let characteristic = NSObject()
        var session = BluetoothSessionIdentity()
        let attempt = session.begin(peripheral: peripheral)
        _ = session.registerServices([service], peripheral: peripheral, sessionID: attempt)
        _ = session.select(characteristic: characteristic, service: service, peripheral: peripheral, sessionID: attempt)
        session.invalidate()

        #expect(session.id == nil)
        #expect(!session.acceptsCurrentPeripheral(peripheral))
        #expect(!session.accepts(peripheral: peripheral, sessionID: attempt))
        #expect(!session.accepts(service: service, peripheral: peripheral, sessionID: attempt))
        #expect(!session.accepts(characteristic: characteristic, peripheral: peripheral, sessionID: attempt))
    }

    @Test func stopReplacesPendingMotionAndCannotBeReplacedByPeriodicMotion() throws {
        let writes = BluetoothWriteState()
        var motionResults: [TransportWriteResult] = []
        var stopResults: [TransportWriteResult] = []
        let motion = PendingTransportWrite(data: Data([1]), completion: nil, resultCompletion: { motionResults.append($0) })
        let stop = PendingTransportWrite(data: Data([0]), completion: nil, resultCompletion: { stopResults.append($0) })
        #expect(writes.enqueue(motion, isStop: false).accepted)
        let stopping = writes.enqueue(stop, isStop: true)
        #expect(stopping.accepted)
        stopping.replaced?.complete(.superseded)
        #expect(motionResults == [.superseded])
        #expect(stopResults.isEmpty)
        #expect(!writes.enqueue(motion, isStop: false).accepted)
        #expect(!writes.enqueue(stop, isStop: true).accepted)

        let submitted = try #require(writes.takeReadyWrite(requiresResponse: false))
        #expect(submitted.data == Data([0]))
        submitted.complete(.submitted)
        #expect(stopResults == [.submitted])
        #expect(writes.isStopping)
        #expect(writes.takeReadyWrite(requiresResponse: false) == nil)
    }

    @Test func responseWriteKeepsStopQueuedUntilPrecedingWriteIsAcknowledged() throws {
        let writes = BluetoothWriteState()
        var results: [TransportWriteResult] = []
        _ = writes.enqueue(PendingTransportWrite(data: Data([1]), completion: nil), isStop: false)
        #expect(writes.takeReadyWrite(requiresResponse: true)?.data == Data([1]))
        _ = writes.enqueue(PendingTransportWrite(data: Data([0]), completion: nil, resultCompletion: { results.append($0) }), isStop: true)
        #expect(writes.takeReadyWrite(requiresResponse: true) == nil)
        #expect(results.isEmpty)

        writes.takeAcknowledgedWrite()?.complete(.acknowledged)
        let stop = try #require(writes.takeReadyWrite(requiresResponse: true))
        #expect(stop.data == Data([0]))
        #expect(results.isEmpty)
        writes.takeAcknowledgedWrite()?.complete(.acknowledged)
        #expect(results == [.acknowledged])
        #expect(writes.takeAcknowledgedWrite() == nil)
    }

    @Test func cleanupClearsOwnedStateBeforeInvokingReentrantCompletions() {
        let writes = BluetoothWriteState()
        var results: [TransportWriteResult] = []
        let first = PendingTransportWrite(data: Data([1]), completion: {
            // A client reconnects and queues a new write from an old completion.
            _ = writes.enqueue(PendingTransportWrite(data: Data([9]), completion: nil), isStop: false)
        }, resultCompletion: { results.append($0) })
        _ = writes.enqueue(first, isStop: false)
        _ = writes.takeReadyWrite(requiresResponse: true)
        _ = writes.enqueue(PendingTransportWrite(data: Data([0]), completion: nil, resultCompletion: { results.append($0) }), isStop: true)

        let removed = writes.removeAll()
        #expect(!writes.isStopping)
        #expect(writes.takeAcknowledgedWrite() == nil)
        removed.forEach { $0.complete(.cancelled) }

        #expect(results == [.cancelled, .cancelled])
        #expect(writes.takeReadyWrite(requiresResponse: false)?.data == Data([9]))
        #expect(writes.removeAll().isEmpty)
    }
}
