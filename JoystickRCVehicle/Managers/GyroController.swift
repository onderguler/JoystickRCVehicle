import Combine
import CoreMotion
import Foundation

final class GyroController: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var isAvailable: Bool

    var sensitivity: Double = 50

    private let motionManager = CMMotionManager()
    private var startPosition: TurretPosition = .zero
    private var accumulatedX = 0.0
    private var accumulatedY = 0.0
    private var onChange: ((TurretPosition) -> Void)?

    init() {
        isAvailable = motionManager.isGyroAvailable
    }

    @discardableResult
    func start(
        from position: TurretPosition,
        sensitivity: Double,
        onChange: @escaping (TurretPosition) -> Void
    ) -> Bool {
        guard motionManager.isGyroAvailable else {
            isAvailable = false
            return false
        }

        stop()
        self.sensitivity = sensitivity
        startPosition = position
        accumulatedX = 0
        accumulatedY = 0
        self.onChange = onChange
        isActive = true

        motionManager.gyroUpdateInterval = 0.05
        motionManager.startGyroUpdates(to: .main) { [weak self] data, _ in
            guard let self, self.isActive, let data else { return }
            let interval = self.motionManager.gyroUpdateInterval
            self.accumulatedX = ControlMath.clamp(
                self.accumulatedX + data.rotationRate.x * interval * 0.4,
                minimum: -1,
                maximum: 1
            )
            self.accumulatedY = ControlMath.clamp(
                self.accumulatedY + data.rotationRate.y * interval * 0.4,
                minimum: -1,
                maximum: 1
            )

            self.onChange?(TurretPosition(
                x: ControlMath.turretTarget(
                    start: self.startPosition.x,
                    input: self.accumulatedX,
                    sensitivity: self.sensitivity
                ),
                y: ControlMath.turretTarget(
                    start: self.startPosition.y,
                    input: self.accumulatedY,
                    sensitivity: self.sensitivity
                )
            ))
        }
        return true
    }

    func stop() {
        motionManager.stopGyroUpdates()
        isActive = false
        accumulatedX = 0
        accumulatedY = 0
        onChange = nil
    }
}
