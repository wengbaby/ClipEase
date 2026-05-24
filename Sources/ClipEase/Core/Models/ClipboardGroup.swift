import Foundation

struct ClipboardGroup: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var colorHex: String
    var iconName: String
    var sortOrder: Int
    let createdAt: Date
    var updatedAt: Date

    static let defaultName = "新分组"

    static let defaultColors = [
        "#0A84FF",
        "#2E8CFF",
        "#007AFF",
        "#5856D6",
        "#5E5CE6",
        "#AF52DE",
        "#30D158",
        "#34C759",
        "#63E6BE",
        "#00C7BE",
        "#32ADE6",
        "#FF9F0A",
        "#FFD60A",
        "#FFCC00",
        "#FF6B35",
        "#FF375F",
        "#FF2D55",
        "#A2845E",
        "#BF5AF2",
        "#64D2FF"
    ]

    static let defaultIcons = [
        "tray.full",
        "bookmark",
        "bookmark.fill",
        "doc.text",
        "doc.plaintext",
        "doc.richtext",
        "doc.on.doc",
        "doc.badge.plus",
        "clipboard",
        "list.bullet.clipboard",
        "link",
        "link.circle",
        "text.quote",
        "textformat",
        "number",
        "calendar",
        "clock",
        "alarm",
        "photo",
        "photo.on.rectangle",
        "camera",
        "film",
        "music.note",
        "play.rectangle",
        "folder",
        "folder.fill",
        "archivebox",
        "shippingbox",
        "tag",
        "tag.fill",
        "paperclip",
        "pin",
        "pin.fill",
        "cart",
        "bag",
        "creditcard",
        "gift",
        "heart",
        "heart.fill",
        "flag",
        "flag.fill",
        "briefcase",
        "case",
        "book",
        "books.vertical",
        "graduationcap",
        "hammer",
        "wrench.and.screwdriver",
        "gearshape",
        "lightbulb",
        "lightbulb.fill",
        "paintpalette",
        "paintbrush",
        "eyedropper",
        "terminal",
        "curlybraces",
        "chevron.left.forwardslash.chevron.right",
        "person",
        "person.2",
        "person.crop.circle",
        "house",
        "building.2",
        "globe",
        "network",
        "wifi",
        "lock",
        "key",
        "bell",
        "megaphone",
        "envelope",
        "phone",
        "message",
        "bubble.left.and.bubble.right",
        "paperplane",
        "location",
        "map",
        "safari",
        "sparkles",
        "wand.and.rays",
        "bolt",
        "flame",
        "leaf",
        "drop",
        "moon",
        "sun.max",
        "cloud",
        "checkmark.circle",
        "xmark.circle",
        "exclamationmark.triangle",
        "questionmark.circle"
    ]

    static func makeDefault(name: String = defaultName, sortOrder: Int) -> ClipboardGroup {
        let now = Date()
        return ClipboardGroup(
            id: UUID(),
            name: name,
            colorHex: defaultColors.randomElement() ?? "#0A84FF",
            iconName: defaultIcons.randomElement() ?? "tray.full",
            sortOrder: sortOrder,
            createdAt: now,
            updatedAt: now
        )
    }
}
