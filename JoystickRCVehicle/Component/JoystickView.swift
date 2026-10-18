import SwiftUI

struct FloatingJoystickArea: View {
    enum Kind {
        case movement
        case turret
    }

    let kind: Kind
    let sensitivity: Double
    let turretPosition: TurretPosition
    var isEnabled = true
    var onMovement: (MotorOutput) -> Void = { _ in }
    var onTurret: (TurretPosition) -> Void = { _ in }

    @State private var isActive = false
    @State private var basePosition = CGPoint.zero
    @State private var thumbOffset = CGSize.zero
    @State private var gestureStartTurret = TurretPosition.zero

    var body: some View {
        GeometryReader { geometry in
            let diameter = joystickDiameter(for: geometry.size)
            let maximumOffset = diameter * 0.38

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(isEnabled ? 0.07 : 0.035))

                if !isEnabled {
                    Image(systemName: "gyroscope")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary.opacity(0.5))
                }

                if isActive {
                    Circle()
                        .fill(Color.secondary.opacity(0.14))
                        .overlay(Circle().stroke(Color.secondary.opacity(0.35), lineWidth: 1))
                        .frame(width: diameter, height: diameter)
                        .position(basePosition)

                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: diameter * 0.24, height: diameter * 0.24)
                        .position(
                            x: basePosition.x + thumbOffset.width,
                            y: basePosition.y + thumbOffset.height
                        )
                        .shadow(radius: 2, y: 1)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        guard isEnabled else { return }

                        let activeBase: CGPoint
                        let startTurret: TurretPosition
                        if isActive {
                            activeBase = basePosition
                            startTurret = gestureStartTurret
                        } else {
                            activeBase = clampedBase(
                                value.startLocation,
                                in: geometry.size,
                                diameter: diameter
                            )
                            startTurret = turretPosition
                            basePosition = activeBase
                            gestureStartTurret = startTurret
                            isActive = true
                        }

                        let rawOffset = value.translation
                        let limitedOffset = circularlyLimited(rawOffset, maximum: maximumOffset)
                        thumbOffset = limitedOffset

                        let normalizedX = Double(limitedOffset.width / maximumOffset)
                        let normalizedY = Double(-limitedOffset.height / maximumOffset)
                        switch kind {
                        case .movement:
                            onMovement(ControlMath.movementOutput(
                                x: normalizedX,
                                y: normalizedY,
                                sensitivity: sensitivity
                            ))
                        case .turret:
                            onTurret(TurretPosition(
                                x: ControlMath.turretTarget(
                                    start: startTurret.x,
                                    input: -normalizedX,
                                    sensitivity: sensitivity
                                ),
                                y: ControlMath.turretTarget(
                                    start: startTurret.y,
                                    input: normalizedY,
                                    sensitivity: sensitivity
                                )
                            ))
                        }
                    }
                    .onEnded { _ in
                        if kind == .movement {
                            onMovement(.zero)
                        }
                        isActive = false
                        thumbOffset = .zero
                    }
            )
            .accessibilityIdentifier(kind == .movement ? "movementJoystickArea" : "turretJoystickArea")
        }
    }

    private func joystickDiameter(for size: CGSize) -> CGFloat {
        min(220, max(72, min(size.width, size.height) * 0.72))
    }

    private func clampedBase(_ point: CGPoint, in size: CGSize, diameter: CGFloat) -> CGPoint {
        let margin = diameter / 2 + 6
        return CGPoint(
            x: clampedAxis(point.x, length: size.width, margin: margin),
            y: clampedAxis(point.y, length: size.height, margin: margin)
        )
    }

    private func clampedAxis(_ value: CGFloat, length: CGFloat, margin: CGFloat) -> CGFloat {
        guard length > margin * 2 else { return length / 2 }
        return min(max(value, margin), length - margin)
    }

    private func circularlyLimited(_ value: CGSize, maximum: CGFloat) -> CGSize {
        let magnitude = hypot(value.width, value.height)
        guard magnitude > maximum, magnitude > 0 else { return value }
        let scale = maximum / magnitude
        return CGSize(width: value.width * scale, height: value.height * scale)
    }
}
