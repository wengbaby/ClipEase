import Foundation

@MainActor
final class ClipboardHistoryStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    private let maxInMemoryItems = 80
    private var recentHashes: Set<String> = []

    func addText(_ text: String, sourceApp: SourceAppInfo) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            return
        }

        let hash = "\(sourceApp.bundleID ?? "unknown"):\(normalizedText)"
        guard !recentHashes.contains(hash) else {
            return
        }

        recentHashes.insert(hash)

        let item = ClipboardItem(
            id: UUID(),
            type: .text,
            text: normalizedText,
            createdAt: Date(),
            sourceAppName: sourceApp.name,
            sourceBundleID: sourceApp.bundleID,
            iconName: sourceApp.iconName,
            headerColor: sourceApp.headerColor
        )

        items.insert(item, at: 0)
        if items.count > maxInMemoryItems {
            items.removeLast(items.count - maxInMemoryItems)
        }
    }
}

