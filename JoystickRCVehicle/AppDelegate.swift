//
//  AppDelegate.swift
//  JoystickRCVehicle
//
//  Created by Onder Guler on 1.02.2025.
//


import UIKit
import FirebaseCore
import FirebaseCrashlytics
import FirebaseAnalytics
import FirebasePerformance

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        FirebaseApp.configure()  // Firebase'i başlat
        return true
    }
}
