import Foundation

final class ClipboardSelfWriteGuard: @unchecked Sendable {
    private var skippedTexts: Set<String> = []
    private var skippedImageHashes: Set<String> = []
    private var skippedFilePathSets: Set<String> = []

    func skipText(_ text: String) {
        let normalizedText = Self.normalizedText(text)
        guard !normalizedText.isEmpty else {
            return
        }
        skippedTexts.insert(normalizedText)
    }

    func consumeText(_ text: String) -> Bool {
        let normalizedText = Self.normalizedText(text)
        guard !normalizedText.isEmpty else {
            return false
        }
        return skippedTexts.remove(normalizedText) != nil
    }

    func skipImageHash(_ hash: String?) {
        guard let hash,
              !hash.isEmpty else {
            return
        }
        skippedImageHashes.insert(hash)
    }

    func consumeImageHash(_ hash: String?) -> Bool {
        guard let hash,
              !hash.isEmpty else {
            return false
        }
        return skippedImageHashes.remove(hash) != nil
    }

    func skipFiles(_ urls: [URL]) {
        let key = Self.filePathSetKey(for: urls)
        guard !key.isEmpty else {
            return
        }
        skippedFilePathSets.insert(key)
    }

    func consumeFiles(_ urls: [URL]) -> Bool {
        let key = Self.filePathSetKey(for: urls)
        guard !key.isEmpty else {
            return false
        }
        return skippedFilePathSets.remove(key) != nil
    }

    func removeAll() {
        skippedTexts.removeAll()
        skippedImageHashes.removeAll()
        skippedFilePathSets.removeAll()
    }

    static func filePathSetKey(for urls: [URL]) -> String {
        urls
            .map { $0.standardizedFileURL.path }
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: "\u{1F}")
    }

    private static func normalizedText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
