import Foundation
import Testing
@testable import ClipEase

@Test func githubReleaseUpdateCheckerFindsDmgUpdateFromLatestRelease() throws {
    let release = try releaseFixture(
        tagName: "v2.3.151-260623.2100",
        name: "ClipEase 2.3.151 (260623.2100)",
        assetName: "ClipEase-2.3.151-260623.2100.dmg"
    )

    let result = try GitHubReleaseUpdateChecker.result(from: release, currentVersion: "2.3.150")

    guard case .updateAvailable(let info) = result else {
        Issue.record("Expected updateAvailable")
        return
    }

    #expect(info.version == "2.3.151")
    #expect(info.releaseURL.absoluteString == "https://github.com/wengbaby/ClipEase/releases/tag/v2.3.151-260623.2100")
    #expect(info.downloadURL?.absoluteString == "https://github.com/wengbaby/ClipEase/releases/download/v2.3.151-260623.2100/ClipEase-2.3.151-260623.2100.dmg")
}

@Test func githubReleaseUpdateCheckerTreatsSameShortVersionAsUpToDate() throws {
    let release = try releaseFixture(
        tagName: "v2.3.150-260623.2100",
        name: "ClipEase 2.3.150 (260623.2100)",
        assetName: "ClipEase-2.3.150-260623.2100.dmg"
    )

    let result = try GitHubReleaseUpdateChecker.result(from: release, currentVersion: "2.3.150")

    #expect(result == .upToDate(version: "2.3.150"))
}

@Test func githubReleaseUpdateCheckerComparesSemanticVersions() {
    #expect(GitHubReleaseUpdateChecker.compareVersion("2.3.151", to: "2.3.150") == .orderedDescending)
    #expect(GitHubReleaseUpdateChecker.compareVersion("v2.3.150-260623.2100", to: "2.3.150") == .orderedSame)
    #expect(GitHubReleaseUpdateChecker.compareVersion("2.3.9", to: "2.3.10") == .orderedAscending)
}

@Test func githubReleaseUpdateCheckerFallsBackToLatestPageWhenAPIIsRateLimited() async throws {
    let apiURL = URL(string: "https://api.example.test/repos/wengbaby/ClipEase/releases/latest")!
    let latestPageURL = URL(string: "https://github.example.test/wengbaby/ClipEase/releases/latest")!
    let latestTagURL = URL(string: "https://github.example.test/wengbaby/ClipEase/releases/tag/v2.3.160-260708.0012")!
    let session = URLSession.updateCheckerMockSession(
        responses: [
            apiURL: .init(statusCode: 403, data: Data(#"{"message":"API rate limit exceeded"}"#.utf8)),
            latestPageURL: .init(statusCode: 200, data: Data(), responseURL: latestTagURL)
        ]
    )
    let checker = GitHubReleaseUpdateChecker(
        session: session,
        releaseURL: apiURL,
        latestReleasePageURL: latestPageURL
    )

    let result = try await checker.check(currentVersion: "2.3.159")

    guard case .updateAvailable(let info) = result else {
        Issue.record("Expected updateAvailable")
        return
    }

    #expect(info.version == "2.3.160")
    #expect(info.releaseURL == latestTagURL)
    #expect(info.downloadURL == nil)
}

private func releaseFixture(
    tagName: String,
    name: String,
    assetName: String
) throws -> GitHubRelease {
    let json = """
    {
      "tag_name": "\(tagName)",
      "name": "\(name)",
      "html_url": "https://github.com/wengbaby/ClipEase/releases/tag/\(tagName)",
      "published_at": "2026-06-23T13:00:00Z",
      "assets": [
        {
          "name": "\(assetName)",
          "browser_download_url": "https://github.com/wengbaby/ClipEase/releases/download/\(tagName)/\(assetName)"
        }
      ]
    }
    """

    return try JSONDecoder.releaseFixtureDecoder.decode(GitHubRelease.self, from: Data(json.utf8))
}

private extension JSONDecoder {
    static var releaseFixtureDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct MockUpdateCheckerHTTPResponse {
    let statusCode: Int
    let data: Data
    let responseURL: URL?

    init(statusCode: Int, data: Data, responseURL: URL? = nil) {
        self.statusCode = statusCode
        self.data = data
        self.responseURL = responseURL
    }
}

private extension URLSession {
    static func updateCheckerMockSession(responses: [URL: MockUpdateCheckerHTTPResponse]) -> URLSession {
        UpdateCheckerMockURLProtocol.responses = responses
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateCheckerMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class UpdateCheckerMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [URL: MockUpdateCheckerHTTPResponse] = [:]

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let mockResponse = Self.responses[url],
              let response = HTTPURLResponse(
                url: mockResponse.responseURL ?? url,
                statusCode: mockResponse.statusCode,
                httpVersion: nil,
                headerFields: nil
              ) else {
            client?.urlProtocol(self, didFailWithError: AppUpdateCheckError.invalidResponse)
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: mockResponse.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
