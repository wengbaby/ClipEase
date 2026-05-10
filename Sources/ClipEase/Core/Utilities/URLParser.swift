import Foundation

enum URLParser {
    static func url(from text: String) -> URL? {
        let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.contains(where: { $0.isWhitespace }) else {
            return nil
        }

        if let url = URL(string: candidate), isSupported(url) {
            return url
        }

        guard candidate.contains("."),
              let url = URL(string: "https://\(candidate)"),
              isSupported(url) else {
            return nil
        }

        return url
    }

    private static func isSupported(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host(percentEncoded: false) != nil else {
            return false
        }

        return true
    }
}
