import Foundation

/// Utility class for accessing app information from Info.plist
final class AppInfo {
    /// Shared instance
    static let shared = AppInfo()
    
    /// Private initializer
    private init() {
        // Debug logging
        print("📱 App Info Debug:")
        print("CFBundleShortVersionString: \(string(for: "CFBundleShortVersionString") ?? "nil")")
        print("CFBundleVersion: \(string(for: "CFBundleVersion") ?? "nil")")
    }
    
    /// Get a string value from Info.plist
    /// - Parameter key: The key to look up
    /// - Returns: The string value if found, nil otherwise
    private func string(for key: String) -> String? {
        let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
        print("Reading \(key): \(value ?? "nil")")
        return value
    }
    
    /// App name
    var appName: String {
        return string(for: "CFBundleName") ?? "Hush"
    }
    
    /// App version (short version string)
    var version: String {
        return string(for: "CFBundleShortVersionString") ?? "1.0.0"
    }
    
    /// App build number
    var build: String {
        let buildNumber = string(for: "CFBundleVersion") ?? "HX07"
        print("Build number: \(buildNumber)")
        return buildNumber
    }
    
    /// Full version string (version + build)
    var fullVersion: String {
        return "\(version) (\(build))"
    }
    
    /// Bundle version (same as build)
    var bundleVersion: String {
        return build
    }
    
    /// Copyright notice
    var copyright: String {
        return string(for: "NSHumanReadableCopyright") ?? "Copyright © 2024 KaizoKonpaku. All rights reserved."
    }
    
    /// Bundle identifier
    var bundleIdentifier: String {
        return string(for: "CFBundleIdentifier") ?? "com.kaizokonpaku.hush"
    }
} 