import Foundation

struct AppUpdateInfo: Equatable, Sendable {
    let version: String
    let releaseURL: URL
    let downloadURL: URL?
    let publishedAt: Date?
}

enum AppUpdateCheckResult: Equatable, Sendable {
    case upToDate(version: String)
    case updateAvailable(AppUpdateInfo)
}

enum AppUpdateCheckError: Error, Equatable {
    case invalidResponse
    case missingReleaseVersion
}

protocol AppUpdateChecking: Sendable {
    func check(currentVersion: String) async throws -> AppUpdateCheckResult
}

struct GitHubReleaseUpdateChecker: AppUpdateChecking {
    private let session: URLSession
    private let releaseURL: URL

    init(
        session: URLSession = .shared,
        releaseURL: URL = URL(string: "https://api.github.com/repos/wengbaby/ClipEase/releases/latest")!
    ) {
        self.session = session
        self.releaseURL = releaseURL
    }

    func check(currentVersion: String) async throws -> AppUpdateCheckResult {
        var request = URLRequest(url: releaseURL, timeoutInterval: 8)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ClipEase/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw AppUpdateCheckError.invalidResponse
        }

        let release = try JSONDecoder.githubReleaseDecoder.decode(GitHubRelease.self, from: data)
        return try Self.result(from: release, currentVersion: currentVersion)
    }

    static func result(from release: GitHubRelease, currentVersion: String) throws -> AppUpdateCheckResult {
        guard let latestVersion = release.version else {
            throw AppUpdateCheckError.missingReleaseVersion
        }

        if compareVersion(latestVersion, to: currentVersion) == .orderedDescending {
            return .updateAvailable(
                AppUpdateInfo(
                    version: latestVersion,
                    releaseURL: release.htmlURL,
                    downloadURL: release.dmgAssetURL,
                    publishedAt: release.publishedAt
                )
            )
        }

        return .upToDate(version: currentVersion)
    }

    static func compareVersion(_ lhs: String, to rhs: String) -> ComparisonResult {
        let left = semanticVersionParts(from: lhs)
        let right = semanticVersionParts(from: rhs)
        let count = max(left.count, right.count)

        for index in 0..<count {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0
            if leftValue < rightValue {
                return .orderedAscending
            }
            if leftValue > rightValue {
                return .orderedDescending
            }
        }

        return .orderedSame
    }

    private static func semanticVersionParts(from value: String) -> [Int] {
        let cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^[^\d]*"#, with: "", options: .regularExpression)
        let version = cleaned.split(separator: "-", maxSplits: 1).first.map(String.init) ?? cleaned

        return version
            .split(separator: ".")
            .map { part in
                let digits = part.prefix { $0.isNumber }
                return Int(digits) ?? 0
            }
    }
}

struct GitHubRelease: Decodable, Sendable {
    let tagName: String
    let name: String?
    let htmlURL: URL
    let publishedAt: Date?
    let assets: [GitHubReleaseAsset]

    var version: String? {
        Self.versionString(from: tagName) ?? name.flatMap(Self.versionString(from:))
    }

    var dmgAssetURL: URL? {
        assets.first { asset in
            asset.name.lowercased().hasSuffix(".dmg")
        }?.browserDownloadURL
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case assets
    }

    private static func versionString(from value: String) -> String? {
        guard let range = value.range(
            of: #"\d+(?:\.\d+){1,3}"#,
            options: .regularExpression
        ) else {
            return nil
        }

        return String(value[range])
    }
}

struct GitHubReleaseAsset: Decodable, Sendable {
    let name: String
    let browserDownloadURL: URL

    private enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

private extension JSONDecoder {
    static var githubReleaseDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
