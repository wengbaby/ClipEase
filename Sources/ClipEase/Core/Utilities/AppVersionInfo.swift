import Foundation

enum AppVersionInfo {
    static var displayVersion: String {
        "\(shortVersion)(\(buildVersion))"
    }

    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    static var buildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }

    static let githubURL = URL(string: "https://github.com/wengbaby/ClipEase")
}
