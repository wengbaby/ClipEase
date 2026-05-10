import Foundation

enum ColorParser {
    static func hexColor(from text: String) -> String? {
        let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^#?([0-9a-fA-F]{6}|[0-9a-fA-F]{3})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: candidate,
                range: NSRange(candidate.startIndex..., in: candidate)
              ),
              let range = Range(match.range(at: 1), in: candidate) else {
            return nil
        }

        let rawHex = String(candidate[range]).uppercased()
        if rawHex.count == 3 {
            return "#" + rawHex.map { "\($0)\($0)" }.joined()
        }

        return "#\(rawHex)"
    }
}
