import AppKit

enum PasteboardWriter {
    @discardableResult
    static func writeText(
        _ text: String,
        to pasteboard: NSPasteboard = .general,
        richTextData: Data? = nil,
        skipRecording: ((String) -> Void)? = nil
    ) -> Bool {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            return false
        }

        skipRecording?(normalizedText)
        pasteboard.clearContents()
        if let richTextData {
            pasteboard.setData(richTextData, forType: .rtf)
        }
        return pasteboard.setString(normalizedText, forType: .string)
    }
}
