//
//  BundleExtensions.swift
//  JoystickRCVehicle
//
//  Created by Onder Guler on 6.12.2024.
//

import Foundation

extension Bundle {
    var appVersion: String {
        return (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "Unknown"
    }

    var buildNumber: String {
        return (infoDictionary?["CFBundleVersion"] as? String) ?? "Unknown"
    }
}
