import Foundation

struct LinkMetadata: Sendable {
    let title: String?
    let imageData: Data?
}

struct LinkPageMetadata: Sendable {
    let title: String?
    let html: String
}

enum LinkTitleFetcher {
    static func title(for url: URL) async -> String? {
        await pageMetadata(for: url)?.title
    }

    static func metadata(for url: URL) async -> LinkMetadata {
        guard let pageMetadata = await pageMetadata(for: url) else {
            return LinkMetadata(title: nil, imageData: nil)
        }

        return LinkMetadata(
            title: pageMetadata.title,
            imageData: await fetchPreviewImage(from: pageMetadata.html, baseURL: url)
        )
    }

    static func previewImageData(from pageMetadata: LinkPageMetadata, baseURL: URL) async -> Data? {
        await fetchPreviewImage(from: pageMetadata.html, baseURL: baseURL)
    }

    static func pageMetadata(for url: URL) async -> LinkPageMetadata? {
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

            return LinkPageMetadata(
                title: extractTitle(from: html),
                html: html
            )
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

    private static func fetchPreviewImage(from html: String, baseURL: URL) async -> Data? {
        guard let imageURL = extractPreviewImageURL(from: html, baseURL: baseURL),
              ["http", "https"].contains(imageURL.scheme?.lowercased()) else {
            return nil
        }

        var request = URLRequest(url: imageURL, timeoutInterval: 4)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X) ClipEase/1.0",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<400).contains(httpResponse.statusCode),
                  data.count <= 5_000_000 else {
                return nil
            }

            return data
        } catch {
            return nil
        }
    }

    private static func extractPreviewImageURL(from html: String, baseURL: URL) -> URL? {
        extractSocialPreviewImageURL(from: html, baseURL: baseURL)
            ?? extractSiteIconURL(from: html, baseURL: baseURL)
    }

    private static func extractSocialPreviewImageURL(from html: String, baseURL: URL) -> URL? {
        let metaTags = html.matches(
            pattern: #"<meta\b[^>]*>"#,
            options: [.regularExpression, .caseInsensitive]
        )

        let imageKeys = [
            "og:image",
            "og:image:url",
            "twitter:image",
            "twitter:image:src"
        ]

        for tag in metaTags {
            let property = tag.htmlAttribute("property") ?? tag.htmlAttribute("name")
            guard let property,
                  imageKeys.contains(property.lowercased()),
                  let content = tag.htmlAttribute("content"),
                  let url = URL(string: decodeHTMLEntities(content), relativeTo: baseURL)?.absoluteURL else {
                continue
            }

            return url
        }

        return nil
    }

    private static func extractSiteIconURL(from html: String, baseURL: URL) -> URL? {
        let linkTags = html.matches(
            pattern: #"<link\b[^>]*>"#,
            options: [.regularExpression, .caseInsensitive]
        )

        let preferredIconRels = [
            "fluid-icon",
            "apple-touch-icon",
            "apple-touch-icon-precomposed",
            "icon"
        ]

        for preferredRel in preferredIconRels {
            for tag in linkTags {
                let relValues = (tag.htmlAttribute("rel") ?? "")
                    .lowercased()
                    .split(separator: " ")
                    .map(String.init)

                guard relValues.contains(preferredRel),
                      let href = tag.htmlAttribute("href"),
                      let url = URL(string: decodeHTMLEntities(href), relativeTo: baseURL)?.absoluteURL else {
                    continue
                }

                return url
            }
        }

        return nil
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

private extension String {
    func matches(pattern: String, options: NSString.CompareOptions) -> [String] {
        var results: [String] = []
        var searchRange = startIndex..<endIndex

        while let range = range(of: pattern, options: options, range: searchRange) {
            results.append(String(self[range]))
            searchRange = range.upperBound..<endIndex
        }

        return results
    }

    func htmlAttribute(_ name: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"\b\#(escapedName)\s*=\s*(['"])(.*?)\1"#
        guard let range = range(
            of: pattern,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return nil
        }

        let text = String(self[range])
        guard let equalsIndex = text.firstIndex(of: "=") else {
            return nil
        }

        return text[text.index(after: equalsIndex)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .dropFirst()
            .dropLast()
            .description
    }
}
