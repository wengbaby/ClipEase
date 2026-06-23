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
