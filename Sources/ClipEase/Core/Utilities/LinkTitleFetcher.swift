import CoreFoundation
import Foundation

struct LinkPageMetadata: Sendable {
    let title: String?
    let html: String
    let finalURL: URL
}

struct LinkTitleFetcher: Sendable {
    private let httpClient: any LinkMetadataHTTPFetching
    private let imageDecoder: LinkPreviewImageDecoder

    init(
        httpClient: any LinkMetadataHTTPFetching,
        imageDecoder: LinkPreviewImageDecoder = LinkPreviewImageDecoder()
    ) {
        self.httpClient = httpClient
        self.imageDecoder = imageDecoder
    }

    static func live() -> LinkTitleFetcher {
        LinkTitleFetcher(httpClient: LinkMetadataHTTPClient.live())
    }

    func loadPageMetadata(for url: URL) async -> LinkPageMetadata? {
        do {
            let response = try await httpClient.fetch(url, as: .page)
            guard let html = String(data: response.data, encoding: .utf8)
                    ?? String(data: response.data, encoding: .ascii) else {
                return nil
            }

            return LinkPageMetadata(
                title: Self.extractTitle(from: html),
                html: html,
                finalURL: response.finalURL
            )
        } catch {
            return nil
        }
    }

    func loadPreviewImage(
        from pageMetadata: LinkPageMetadata
    ) async -> LinkPreviewDecodedImage? {
        guard let imageURL = Self.extractPreviewImageURL(
            from: pageMetadata.html,
            baseURL: pageMetadata.finalURL
        ) else {
            return nil
        }

        do {
            let response = try await httpClient.fetch(imageURL, as: .image)
            return try imageDecoder.decode(
                response.data,
                declaredMIMEType: response.mimeType
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
        guard text.contains("&"),
              let decoded = CFXMLCreateStringByUnescapingEntities(
                nil,
                text as CFString,
                nil
              ) else {
            return text
        }
        return decoded as String
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
