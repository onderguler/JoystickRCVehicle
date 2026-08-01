import Foundation

protocol VehicleTransport: AnyObject {
    var connectionState: VehicleConnectionState { get }
    var stateDidChange: ((VehicleConnectionState) -> Void)? { get set }

    func send(_ data: Data, completion: (() -> Void)?)
    func disconnect()
}

struct PendingTransportWrite {
    let data: Data
    let completion: (() -> Void)?
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
