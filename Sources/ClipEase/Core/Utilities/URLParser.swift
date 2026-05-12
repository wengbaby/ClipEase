import Foundation

enum URLParser {
    static func url(from text: String) -> URL? {
        let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.contains(where: { $0.isWhitespace }) else {
            return nil
        }

        if hasExplicitHTTPScheme(candidate),
           let url = URL(string: candidate),
           isSupported(url) {
            return url
        }

        guard isLikelyBareURL(candidate),
              let url = URL(string: "https://\(candidate)"),
              isSupported(url) else {
            return nil
        }

        return url
    }

    private static func hasExplicitHTTPScheme(_ candidate: String) -> Bool {
        candidate.localizedCaseInsensitiveCompare("http://") == .orderedSame
            || candidate.localizedCaseInsensitiveCompare("https://") == .orderedSame
            || candidate.lowercased().hasPrefix("http://")
            || candidate.lowercased().hasPrefix("https://")
    }

    private static func isLikelyBareURL(_ candidate: String) -> Bool {
        guard !candidate.contains("_"),
              !candidate.hasPrefix("."),
              !candidate.hasSuffix(".") else {
            return false
        }

        let lowercased = candidate.lowercased()
        let host = String(lowercased.split(separator: "/", maxSplits: 1).first ?? "")
        guard host.isHostLikeDomain else {
            return false
        }

        if candidate.split(separator: "/", maxSplits: 1).count == 1,
           let fileExtension = host.split(separator: ".").last,
           Self.commonDocumentExtensions.contains(String(fileExtension)) {
            return false
        }

        return true
    }

    private static func isSupported(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host(percentEncoded: false),
              host.isHostLikeDomain else {
            return false
        }

        return true
    }

    private static let commonDocumentExtensions: Set<String> = [
        "md", "txt", "rtf", "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
        "json", "xml", "csv", "swift", "js", "ts", "css", "html", "png", "jpg",
        "jpeg", "gif", "webp", "svg", "heic", "zip", "dmg"
    ]
}

private extension String {
    var isHostLikeDomain: Bool {
        let parts = split(separator: ".")
        guard parts.count >= 2,
              let last = parts.last,
              (2...24).contains(last.count),
              last.allSatisfy(\.isLetter) else {
            return false
        }

        return parts.allSatisfy { part in
            guard !part.isEmpty,
                  !part.hasPrefix("-"),
                  !part.hasSuffix("-") else {
                return false
            }

            return part.allSatisfy { character in
                character.isLetter || character.isNumber || character == "-"
            }
        }
    }
}
