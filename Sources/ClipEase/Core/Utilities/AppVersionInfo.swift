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
    static let githubReleasesURL = URL(string: "https://github.com/wengbaby/ClipEase/releases")
    static let githubSupportURL = URL(string: "https://github.com/wengbaby/ClipEase#%E6%94%AF%E6%8C%81%E4%B8%8E%E4%BA%A4%E6%B5%81")
}
