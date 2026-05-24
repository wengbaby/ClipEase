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

        return nil
    }

    private static func hasExplicitHTTPScheme(_ candidate: String) -> Bool {
        let lowercased = candidate.lowercased()
        return lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://")
    }

    private static func isSupported(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host(percentEncoded: false),
              !host.isEmpty,
              isSupportedHost(host) else {
            return false
        }

        return true
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host.isHostLikeDomain || host.isIPv4Address || host.localizedCaseInsensitiveCompare("localhost") == .orderedSame
    }

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

    var isIPv4Address: Bool {
        let parts = split(separator: ".")
        guard parts.count == 4 else {
            return false
        }

        return parts.allSatisfy { part in
            guard let value = Int(part), (0...255).contains(value) else {
                return false
            }

            return String(value) == part || part == "0"
        }
    }
}
