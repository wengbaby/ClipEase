import Foundation

enum LinkTitleFetcher {
    static func title(for url: URL) async -> String? {
        var request = URLRequest(url: url, timeoutInterval: 4)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X) ClipEase/1.0",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<400).contains(httpResponse.statusCode),
                  let html = String(data: data.prefix(256_000), encoding: .utf8)
                    ?? String(data: data.prefix(256_000), encoding: .ascii) else {
                return nil
            }

            return extractTitle(from: html)
        } catch {
            return nil
        }
    }

    private static func extractTitle(from html: String) -> String? {
        guard let range = html.range(
            of: #"<title[^>]*>(.*?)</title>"#,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return nil
        }

        let title = html[range]
            .replacingOccurrences(
                of: #"</?title[^>]*>"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return title.isEmpty ? nil : decodeHTMLEntities(title)
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let attributedString = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return text
        }

        return attributedString.string
    }
}
