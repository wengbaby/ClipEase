import AppKit
import Foundation
import SwiftUI

enum AppearanceColorTheme: String, CaseIterable, Identifiable, Sendable {
    case light
    case dark
    case system

    var id: Self { self }

    var title: String {
        switch self {
        case .light: "浅色"
        case .dark: "深色"
        case .system: "跟随主题"
        }
    }

    var windowAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AppearanceMaterialTheme: String, CaseIterable, Identifiable, Sendable {
    case liquidGlass
    case regular
    case frosted
    case deepSpace
    case prism
    case holographic
    case chrome
    case jelly
    case paper
    case crystal
    case sunset
    case aurora
    case softLight
    case ice
    case ink
    case amber
    case ocean
    case mica
    case obsidian
    case borderless
    case velvet
    case neon
    case pearl
    case graphite
    case roseQuartz
    case lagoon
    case ember
    case midnight
    case champagne
    case ultraviolet

    var id: Self { self }

    var title: String {
        switch self {
        case .liquidGlass: "液态玻璃"
        case .regular: "普通"
        case .frosted: "霜雾"
        case .deepSpace: "深空"
        case .prism: "棱镜"
        case .holographic: "全息"
        case .chrome: "铬金属"
        case .jelly: "果冻"
        case .paper: "纸感"
        case .crystal: "水晶"
        case .sunset: "日落"
        case .aurora: "极光"
        case .softLight: "柔光"
        case .ice: "冰川"
        case .ink: "墨影"
        case .amber: "琥珀"
        case .ocean: "海洋"
        case .mica: "云母"
        case .obsidian: "黑曜石"
        case .borderless: "无边界"
        case .velvet: "天鹅绒"
        case .neon: "霓虹"
        case .pearl: "珍珠"
        case .graphite: "石墨"
        case .roseQuartz: "玫瑰石英"
        case .lagoon: "碧湾"
        case .ember: "余烬"
        case .midnight: "午夜"
        case .champagne: "香槟"
        case .ultraviolet: "紫外光"
        }
    }

    var gradient: LinearGradient {
        let colors: [Color]
        switch self {
        case .liquidGlass: colors = [.white.opacity(0.78), .cyan.opacity(0.30), .indigo.opacity(0.38)]
        case .regular: colors = [Color(nsColor: .windowBackgroundColor), Color(nsColor: .controlBackgroundColor)]
        case .frosted: colors = [.white.opacity(0.92), .mint.opacity(0.34), .white.opacity(0.62)]
        case .deepSpace: colors = [.black.opacity(0.96), .indigo.opacity(0.90), .purple.opacity(0.72)]
        case .prism: colors = [.yellow.opacity(0.72), .pink.opacity(0.72), .indigo.opacity(0.80)]
        case .holographic: colors = [.pink.opacity(0.72), .cyan.opacity(0.72), .purple.opacity(0.72)]
        case .chrome: colors = [.white.opacity(0.94), .gray.opacity(0.68), .white.opacity(0.86)]
        case .jelly: colors = [.pink.opacity(0.72), .orange.opacity(0.56), .purple.opacity(0.70)]
        case .paper: colors = [.white.opacity(0.90), .brown.opacity(0.18), .white.opacity(0.74)]
        case .crystal: colors = [.white.opacity(0.94), .cyan.opacity(0.34), .blue.opacity(0.48)]
        case .sunset: colors = [.orange.opacity(0.78), .pink.opacity(0.66), .purple.opacity(0.66)]
        case .aurora: colors = [.mint.opacity(0.68), .cyan.opacity(0.64), .purple.opacity(0.70)]
        case .softLight: colors = [.white.opacity(0.90), .yellow.opacity(0.22), .pink.opacity(0.24)]
        case .ice: colors = [.white.opacity(0.92), .cyan.opacity(0.42), .blue.opacity(0.52)]
        case .ink: colors = [.black.opacity(0.90), .gray.opacity(0.72), .indigo.opacity(0.60)]
        case .amber: colors = [.yellow.opacity(0.66), .orange.opacity(0.66), .brown.opacity(0.58)]
        case .ocean: colors = [.cyan.opacity(0.64), .blue.opacity(0.70), .indigo.opacity(0.70)]
        case .mica: colors = [.white.opacity(0.82), .purple.opacity(0.36), .gray.opacity(0.50)]
        case .obsidian: colors = [.black.opacity(0.96), .gray.opacity(0.54), .purple.opacity(0.42)]
        case .borderless: colors = [.clear, .clear]
        case .velvet: colors = [.purple.opacity(0.82), .indigo.opacity(0.70), .black.opacity(0.76)]
        case .neon: colors = [.cyan.opacity(0.88), .purple.opacity(0.82), .pink.opacity(0.76)]
        case .pearl: colors = [.white.opacity(0.96), .pink.opacity(0.28), .cyan.opacity(0.28)]
        case .graphite: colors = [.gray.opacity(0.86), .black.opacity(0.78), .gray.opacity(0.56)]
        case .roseQuartz: colors = [.pink.opacity(0.70), .white.opacity(0.68), .purple.opacity(0.40)]
        case .lagoon: colors = [.mint.opacity(0.72), .cyan.opacity(0.72), .blue.opacity(0.60)]
        case .ember: colors = [.red.opacity(0.74), .orange.opacity(0.76), .black.opacity(0.66)]
        case .midnight: colors = [.black.opacity(0.96), .blue.opacity(0.70), .indigo.opacity(0.74)]
        case .champagne: colors = [.white.opacity(0.88), .yellow.opacity(0.48), .orange.opacity(0.32)]
        case .ultraviolet: colors = [.indigo.opacity(0.84), .purple.opacity(0.82), .pink.opacity(0.60)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var surfaceOpacity: Double {
        switch self {
        case .regular: 0.96
        case .borderless: 0
        case .liquidGlass, .crystal, .ice, .softLight, .pearl, .champagne: 0.68
        default: 0.84
        }
    }
}

enum AppearanceCardStyle: String, CaseIterable, Identifiable {
    case liquidGlass
    case regular
    case frosted
    case deepSpace
    case prism
    case holographic
    case chrome
    case jelly
    case paper
    case crystal
    case sunset
    case aurora
    case softLight
    case ice
    case ink
    case amber
    case ocean
    case mica
    case obsidian
    case borderless
    case velvet
    case neon
    case pearl
    case graphite
    case roseQuartz
    case lagoon
    case ember
    case midnight
    case champagne
    case ultraviolet

    var id: Self { self }

    var title: String {
        materialTheme.title
    }

    var materialTheme: AppearanceMaterialTheme {
        AppearanceMaterialTheme(rawValue: rawValue) ?? .liquidGlass
    }
}

enum AppearanceTypographyRole: String, CaseIterable, Identifiable, Sendable {
    case windowTitle
    case search
    case group
    case toolbarButton
    case card

    var id: Self { self }

    var title: String {
        switch self {
        case .windowTitle: "窗口标题"
        case .search: "搜索框"
        case .group: "分组标签"
        case .toolbarButton: "工具栏按钮"
        case .card: "卡片内容"
        }
    }

    var defaultTypography: AppearanceTypography {
        switch self {
        case .windowTitle: .init(size: 15, weight: .semibold)
        case .search: .init(size: 13, weight: .medium)
        case .group: .init(size: 12, weight: .semibold)
        case .toolbarButton: .init(size: 12, weight: .medium)
        case .card: .init(size: 16, weight: .regular)
        }
    }
}

enum AppearanceTypographyWeight: String, CaseIterable, Identifiable, Sendable {
    case regular
    case medium
    case semibold
    case bold

    var id: Self { self }

    var title: String {
        switch self {
        case .regular: "常规"
        case .medium: "中等"
        case .semibold: "半粗"
        case .bold: "粗体"
        }
    }

    var swiftUIWeight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }

    var appKitWeight: NSFont.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}

struct AppearanceTypography: Equatable, Sendable {
    static let systemFamily = "__system__"
    static let roundedFamily = "__rounded__"
    static let monospacedFamily = "__monospaced__"

    var family: String = systemFamily
    var size: Double
    var weight: AppearanceTypographyWeight

    init(family: String = AppearanceTypography.systemFamily, size: Double, weight: AppearanceTypographyWeight) {
        self.family = family
        self.size = size
        self.weight = weight
    }

    var displayFamilyName: String {
        switch family {
        case Self.systemFamily: "系统默认"
        case Self.roundedFamily: "系统圆角"
        case Self.monospacedFamily: "系统等宽"
        default: family
        }
    }

    var swiftUIFont: Font {
        switch family {
        case Self.roundedFamily:
            .system(size: size, weight: weight.swiftUIWeight, design: .rounded)
        case Self.monospacedFamily:
            .system(size: size, weight: weight.swiftUIWeight, design: .monospaced)
        case Self.systemFamily:
            .system(size: size, weight: weight.swiftUIWeight)
        default:
            .custom(family, size: size).weight(weight.swiftUIWeight)
        }
    }

    var nsFont: NSFont {
        switch family {
        case Self.roundedFamily:
            return .systemFont(ofSize: size, weight: weight.appKitWeight)
        case Self.monospacedFamily:
            return .monospacedSystemFont(ofSize: size, weight: weight.appKitWeight)
        case Self.systemFamily:
            return .systemFont(ofSize: size, weight: weight.appKitWeight)
        default:
            let descriptor = NSFontDescriptor(fontAttributes: [
                .family: family,
                .traits: [NSFontDescriptor.TraitKey.weight: weight.appKitWeight]
            ])
            return NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size, weight: weight.appKitWeight)
        }
    }

    static var availableFamilies: [String] {
        [systemFamily, roundedFamily, monospacedFamily] + NSFontManager.shared.availableFontFamilies.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

@MainActor
final class AppearanceSettings: ObservableObject {
    static let shared = AppearanceSettings()

    private enum Key {
        static let colorTheme = "appearance.colorTheme"
        static let materialTheme = "appearance.materialTheme"
        static let cardStyle = "appearance.cardStyle"
        static let liquidGlassEnabled = "appearance.liquidGlassEnabled"
        static let windowEffectOpacity = "appearance.windowEffectOpacity"
        static let cardEffectOpacity = "appearance.cardEffectOpacity"
        static let cardHeaderColorIntensity = "appearance.cardHeaderColorIntensity"
        static let groupColorIntensity = "appearance.groupColorIntensity"
        static let toolbarTextContrast = "appearance.toolbarTextContrast"
        static let glassMotionEnabled = "appearance.glassMotionEnabled"
        static let typographyPrefix = "appearance.typography."
    }

    @Published var colorTheme: AppearanceColorTheme { didSet { save() } }
    @Published var materialTheme: AppearanceMaterialTheme { didSet { save() } }
    @Published var cardStyle: AppearanceCardStyle { didSet { save() } }
    @Published var liquidGlassEnabled: Bool { didSet { save() } }
    @Published var windowEffectOpacity: Double { didSet { save() } }
    @Published var cardEffectOpacity: Double { didSet { save() } }
    @Published var cardHeaderColorIntensity: Double { didSet { save() } }
    @Published var groupColorIntensity: Double { didSet { save() } }
    @Published var toolbarTextContrast: Double { didSet { save() } }
    @Published var glassMotionEnabled: Bool { didSet { save() } }
    @Published private(set) var typographies: [AppearanceTypographyRole: AppearanceTypography] { didSet { save() } }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        colorTheme = Self.value(for: Key.colorTheme, from: userDefaults, fallback: .light)
        materialTheme = Self.value(for: Key.materialTheme, from: userDefaults, fallback: .liquidGlass)
        cardStyle = Self.value(for: Key.cardStyle, from: userDefaults, fallback: .liquidGlass)
        liquidGlassEnabled = userDefaults.object(forKey: Key.liquidGlassEnabled) as? Bool ?? true
        windowEffectOpacity = Self.opacity(for: Key.windowEffectOpacity, from: userDefaults, fallback: 0.68)
        cardEffectOpacity = Self.opacity(for: Key.cardEffectOpacity, from: userDefaults, fallback: 0.84)
        cardHeaderColorIntensity = Self.opacity(for: Key.cardHeaderColorIntensity, from: userDefaults, fallback: 1)
        groupColorIntensity = Self.opacity(for: Key.groupColorIntensity, from: userDefaults, fallback: 1)
        toolbarTextContrast = Self.opacity(for: Key.toolbarTextContrast, from: userDefaults, fallback: 1)
        glassMotionEnabled = userDefaults.object(forKey: Key.glassMotionEnabled) as? Bool ?? true
        typographies = Dictionary(uniqueKeysWithValues: AppearanceTypographyRole.allCases.map { role in
            (role, Self.typography(for: role, from: userDefaults))
        })
        save()
    }

    var windowAppearance: NSAppearance? { colorTheme.windowAppearance }
    var preferredColorScheme: ColorScheme? { colorTheme.preferredColorScheme }

    var usesLiquidGlass: Bool {
        liquidGlassEnabled && HistoryGlassRuntime.supportsNativeGlass
    }

    var liquidGlassUnavailableReason: String? {
        guard liquidGlassEnabled, !HistoryGlassRuntime.supportsNativeGlass else {
            return nil
        }
        return "液态玻璃需要 macOS 26 或更高版本"
    }

    func resetToDefaults() {
        colorTheme = .light
        materialTheme = .liquidGlass
        cardStyle = .liquidGlass
        liquidGlassEnabled = true
        windowEffectOpacity = 0.68
        cardEffectOpacity = 0.84
        cardHeaderColorIntensity = 1
        groupColorIntensity = 1
        toolbarTextContrast = 1
        glassMotionEnabled = true
        typographies = Dictionary(uniqueKeysWithValues: AppearanceTypographyRole.allCases.map { ($0, $0.defaultTypography) })
    }

    func typography(for role: AppearanceTypographyRole) -> AppearanceTypography {
        typographies[role] ?? role.defaultTypography
    }

    func updateTypography(_ typography: AppearanceTypography, for role: AppearanceTypographyRole) {
        var updated = typographies
        updated[role] = AppearanceTypography(
            family: typography.family,
            size: min(max(typography.size, 10), 32),
            weight: typography.weight
        )
        typographies = updated
    }

    private func save() {
        userDefaults.set(colorTheme.rawValue, forKey: Key.colorTheme)
        userDefaults.set(materialTheme.rawValue, forKey: Key.materialTheme)
        userDefaults.set(cardStyle.rawValue, forKey: Key.cardStyle)
        userDefaults.set(liquidGlassEnabled, forKey: Key.liquidGlassEnabled)
        userDefaults.set(windowEffectOpacity, forKey: Key.windowEffectOpacity)
        userDefaults.set(cardEffectOpacity, forKey: Key.cardEffectOpacity)
        userDefaults.set(cardHeaderColorIntensity, forKey: Key.cardHeaderColorIntensity)
        userDefaults.set(groupColorIntensity, forKey: Key.groupColorIntensity)
        userDefaults.set(toolbarTextContrast, forKey: Key.toolbarTextContrast)
        userDefaults.set(glassMotionEnabled, forKey: Key.glassMotionEnabled)
        for role in AppearanceTypographyRole.allCases {
            let typography = typography(for: role)
            let prefix = Key.typographyPrefix + role.rawValue + "."
            userDefaults.set(typography.family, forKey: prefix + "family")
            userDefaults.set(typography.size, forKey: prefix + "size")
            userDefaults.set(typography.weight.rawValue, forKey: prefix + "weight")
        }
    }

    private static func value<Value: RawRepresentable>(
        for key: String,
        from defaults: UserDefaults,
        fallback: Value
    ) -> Value where Value.RawValue == String {
        guard let rawValue = defaults.string(forKey: key),
              let value = Value(rawValue: rawValue) else {
            return fallback
        }
        return value
    }

    private static func opacity(for key: String, from defaults: UserDefaults, fallback: Double) -> Double {
        guard let value = defaults.object(forKey: key) as? Double else {
            return fallback
        }
        return min(max(value, 0), 1)
    }

    private static func typography(for role: AppearanceTypographyRole, from defaults: UserDefaults) -> AppearanceTypography {
        let fallback = role.defaultTypography
        let prefix = Key.typographyPrefix + role.rawValue + "."
        let family = defaults.string(forKey: prefix + "family") ?? fallback.family
        let size = fontSize(for: prefix + "size", from: defaults, fallback: fallback.size)
        let weight = defaults.string(forKey: prefix + "weight").flatMap(AppearanceTypographyWeight.init(rawValue:)) ?? fallback.weight
        return AppearanceTypography(family: family, size: min(max(size, 10), 32), weight: weight)
    }

    private static func fontSize(for key: String, from defaults: UserDefaults, fallback: Double) -> Double {
        guard let value = defaults.object(forKey: key) as? Double else {
            return fallback
        }
        return min(max(value, 10), 32)
    }
}

@MainActor
enum AppearanceWindowApplicator {
    static func apply(_ appearance: NSAppearance?, to window: NSWindow?) {
        guard let window else {
            return
        }

        window.appearance = appearance
        window.contentView?.appearance = appearance
        window.contentView?.needsDisplay = true
        window.invalidateShadow()
    }
}
