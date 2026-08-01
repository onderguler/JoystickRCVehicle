import CoreGraphics
import Foundation

struct MotorOutput: Equatable {
    var left: Int
    var right: Int

    static let zero = MotorOutput(left: 0, right: 0)
}

struct TurretPosition: Equatable {
    var x: Int
    var y: Int

    static let zero = TurretPosition(x: 0, y: 0)
}

enum ControlMath {
    static func sensitivityExponent(
        for sensitivity: Double,
        precisionExponent: Double = 2.5
    ) -> Double {
        let normalized = clamp(sensitivity / 100.0, minimum: 0, maximum: 1)
        if normalized <= 0.5 {
            return precisionExponent - ((precisionExponent - 1) * normalized * 2)
        }
        return 1.5 - normalized
    }

    static func applySensitivity(
        to value: Double,
        sensitivity: Double,
        deadZone: Double = 0,
        precisionExponent: Double = 2.5
    ) -> Double {
        let clamped = clamp(value, minimum: -1, maximum: 1)
        let magnitude = abs(clamped)
        let clampedDeadZone = clamp(deadZone, minimum: 0, maximum: 0.95)
        guard magnitude > clampedDeadZone else { return 0 }

        let adjustedMagnitude = (magnitude - clampedDeadZone) / (1 - clampedDeadZone)
        let curvedMagnitude = pow(
            adjustedMagnitude,
            sensitivityExponent(
                for: sensitivity,
                precisionExponent: precisionExponent
            )
        )
        return clamped < 0 ? -curvedMagnitude : curvedMagnitude
    }

    static func movementOutput(x: Double, y: Double, sensitivity: Double) -> MotorOutput {
        let rawMagnitude = min(1, hypot(x, y))
        guard rawMagnitude > 0 else { return .zero }

        let curvedMagnitude = applySensitivity(
            to: rawMagnitude,
            sensitivity: sensitivity,
            deadZone: 0.03
        )
        guard curvedMagnitude > 0 else { return .zero }

        let directionX = x / rawMagnitude
        let directionY = y / rawMagnitude
        let turn = directionX * curvedMagnitude
        let forward = directionY * curvedMagnitude

        var left = forward + turn
        var right = forward - turn
        let normalization = max(1, abs(left), abs(right))
        left /= normalization
        right /= normalization

        return MotorOutput(
            left: clamp(Int((left * 99).rounded()), minimum: -99, maximum: 99),
            right: clamp(Int((right * 99).rounded()), minimum: -99, maximum: 99)
        )
    }

    static func turretTarget(start: Int, input: Double, sensitivity: Double) -> Int {
        let start = clamp(start, minimum: -254, maximum: 254)
        let curvedInput = applySensitivity(
            to: input,
            sensitivity: sensitivity,
            deadZone: 0.02,
            precisionExponent: 4
        )

        let target: Double
        if curvedInput >= 0 {
            target = Double(start) + curvedInput * Double(254 - start)
        } else {
            target = Double(start) + curvedInput * Double(start + 254)
        }
        return clamp(Int(target.rounded()), minimum: -254, maximum: 254)
    }

    static func clamp<T: Comparable>(_ value: T, minimum: T, maximum: T) -> T {
        Swift.max(minimum, Swift.min(maximum, value))
    }
}
