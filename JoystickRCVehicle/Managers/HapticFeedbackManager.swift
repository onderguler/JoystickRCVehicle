//
//  HapticFeedbackManager.swift
//  JoystickRCVehicle
//
//  Created by Onder Guler on 6.12.2024.
//


import UIKit

class HapticFeedbackManager {
    static let shared = HapticFeedbackManager()

    func triggerImpact(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    func triggerNotification(type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}
