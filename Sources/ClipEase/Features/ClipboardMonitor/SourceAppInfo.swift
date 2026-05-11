import AppKit
import SwiftUI

struct SourceAppInfo: Sendable {
    let name: String
    let bundleID: String?
    let iconName: String
    let iconFileName: String?
    let headerColorHex: String

    var headerColor: Color {
        Color.clipeaseHex(headerColorHex)
    }

    static var current: SourceAppInfo {
        let app = NSWorkspace.shared.runningApplications.first { app in
            app.isActive && app.bundleIdentifier != Bundle.main.bundleIdentifier
        } ?? NSWorkspace.shared.frontmostApplication

        guard let app else {
            return SourceAppInfo(
                name: "未知应用",
                bundleID: nil,
                iconName: "app.fill",
                iconFileName: nil,
                headerColorHex: "#2E8CFF"
            )
        }

        let cachedIcon = AppIconCache.cacheIcon(for: app)
        return SourceAppInfo(
            name: app.localizedName ?? "未知应用",
            bundleID: app.bundleIdentifier,
            iconName: iconName(for: app.bundleIdentifier),
            iconFileName: cachedIcon?.fileName,
            headerColorHex: cachedIcon?.dominantColorHex ?? headerColorHex(for: app.bundleIdentifier)
        )
    }

    static let clipease = SourceAppInfo(
        name: "轻贴",
        bundleID: "com.clipease.app",
        iconName: "doc.on.clipboard",
        iconFileName: nil,
        headerColorHex: "#2E8CFF"
    )

    private static func iconName(for bundleID: String?) -> String {
        guard let bundleID else {
            return "app.fill"
        }

        if bundleID.contains("Safari") {
            return "safari.fill"
        }
        if bundleID.contains("Notes") {
            return "note.text"
        }
        if bundleID.contains("TextEdit") {
            return "text.alignleft"
        }
        if bundleID.contains("Messages") || bundleID.contains("WeChat") {
            return "message.fill"
        }
        if bundleID.contains("Xcode") {
            return "hammer.fill"
        }
        if bundleID.contains("com.apple.finder") {
            return "folder.fill"
        }
        return "app.fill"
    }

    private static func headerColorHex(for bundleID: String?) -> String {
        guard let bundleID else {
            return "#2E8CFF"
        }

        if bundleID.contains("Safari") {
            return "#00B8A8"
        }
        if bundleID.contains("Notes") {
            return "#FAC22E"
        }
        if bundleID.contains("Messages") || bundleID.contains("WeChat") {
            return "#0AB361"
        }
        if bundleID.contains("Xcode") {
            return "#1973F2"
        }
        if bundleID.contains("com.apple.finder") {
            return "#338FFF"
        }
        return "#2E8CFF"
    }
}
