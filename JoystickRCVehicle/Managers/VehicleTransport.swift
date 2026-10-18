import Foundation

enum TransportWriteResult: Equatable {
    /// Accepted by the local transport; this is not a vehicle-level acknowledgement.
    case submitted
    /// Transport/GATT acknowledgement only; not proof that the vehicle applied it.
    case acknowledged
    case superseded
    case cancelled
    case failed
}

protocol VehicleTransport: AnyObject {
    var connectionState: VehicleConnectionState { get }
    var stateDidChange: ((VehicleConnectionState) -> Void)? { get set }
    /// Changes before a new connection attempt, including attempts to the same device.
    var connectionSessionID: UUID? { get }

    /// Legacy completion means settled (including replacement/cancellation), not delivered.
    func send(_ data: Data, completion: (() -> Void)?)
    func sendStop(_ data: Data, completion: @escaping (TransportWriteResult) -> Void)
    func disconnect()
}

extension VehicleTransport {
    var connectionSessionID: UUID? { nil }

    func sendStop(_ data: Data, completion: @escaping (TransportWriteResult) -> Void) {
        // Older transports cannot prove submission. Let the coordinator's watchdog
        // bound the wait rather than mistake a cleanup callback for delivery.
        send(data, completion: nil)
    }
}

struct PendingTransportWrite {
    let data: Data
    let completion: (() -> Void)?
    let resultCompletion: ((TransportWriteResult) -> Void)?

    init(
        data: Data,
        completion: (() -> Void)?,
        resultCompletion: ((TransportWriteResult) -> Void)? = nil
    ) {
        self.data = data
        self.completion = completion
        self.resultCompletion = resultCompletion
    }

    /// Remove the write from all owned state before calling out to client code.
    func complete(_ result: TransportWriteResult) {
        completion?()
        resultCompletion?(result)
    }
}

final class LatestWriteQueue {
    private var pendingWrite: PendingTransportWrite?

    var isEmpty: Bool { pendingWrite == nil }

    @discardableResult
    func replace(with write: PendingTransportWrite) -> PendingTransportWrite? {
        let replacedWrite = pendingWrite
        pendingWrite = write
        return replacedWrite
    }

    func takeLatest() -> PendingTransportWrite? {
        defer { pendingWrite = nil }
        return pendingWrite
    }

    func removeLatest() -> PendingTransportWrite? {
        takeLatest()
    }
}
