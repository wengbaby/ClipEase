import AppKit
import SwiftUI

struct SourceAppInfo {
    let name: String
    let bundleID: String?
    let iconName: String
    let headerColor: Color

    static var current: SourceAppInfo {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return SourceAppInfo(
                name: "未知应用",
                bundleID: nil,
                iconName: "app.fill",
                headerColor: Color(red: 0.18, green: 0.55, blue: 1.0)
            )
        }

        return SourceAppInfo(
            name: app.localizedName ?? "未知应用",
            bundleID: app.bundleIdentifier,
            iconName: iconName(for: app.bundleIdentifier),
            headerColor: headerColor(for: app.bundleIdentifier)
        )
    }

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

    private static func headerColor(for bundleID: String?) -> Color {
        guard let bundleID else {
            return Color(red: 0.18, green: 0.55, blue: 1.0)
        }

        if bundleID.contains("Safari") {
            return Color(red: 0.00, green: 0.72, blue: 0.66)
        }
        if bundleID.contains("Notes") {
            return Color(red: 0.98, green: 0.76, blue: 0.18)
        }
        if bundleID.contains("Messages") || bundleID.contains("WeChat") {
            return Color(red: 0.04, green: 0.70, blue: 0.38)
        }
        if bundleID.contains("Xcode") {
            return Color(red: 0.10, green: 0.45, blue: 0.95)
        }
        if bundleID.contains("com.apple.finder") {
            return Color(red: 0.20, green: 0.56, blue: 1.0)
        }
        return Color(red: 0.18, green: 0.55, blue: 1.0)
    }
}

