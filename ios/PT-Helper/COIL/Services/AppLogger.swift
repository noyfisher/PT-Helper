import Foundation
import FirebaseCrashlytics
import os

/// Centralized logging using Apple's unified logging system (os.Logger).
/// Logs are visible in Console.app and Xcode console, and are automatically
/// stripped of debug/info messages in production release builds.
enum AppLogger {
    static let api = Logger(subsystem: Bundle.main.bundleIdentifier ?? "COIL", category: "API")
    static let images = Logger(subsystem: Bundle.main.bundleIdentifier ?? "COIL", category: "Images")
    static let data = Logger(subsystem: Bundle.main.bundleIdentifier ?? "COIL", category: "Data")
    static let auth = Logger(subsystem: Bundle.main.bundleIdentifier ?? "COIL", category: "Auth")
    static let rehab = Logger(subsystem: Bundle.main.bundleIdentifier ?? "COIL", category: "Rehab")
    static let ui = Logger(subsystem: Bundle.main.bundleIdentifier ?? "COIL", category: "UI")

    /// Set a custom key-value pair on Crashlytics for crash context.
    /// Use this to annotate the current screen, active plan ID, etc.
    static func setCrashlyticsKey(_ key: String, value: String) {
        Crashlytics.crashlytics().setCustomValue(value, forKey: key)
    }
}
