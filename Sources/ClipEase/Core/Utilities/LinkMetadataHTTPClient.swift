import Foundation

enum LinkMetadataResourceKind: Sendable {
    case page
    case image

    var maximumBodyBytes: Int {
        switch self {
        case .page:
            256_000
        case .image:
            5_000_000
        }
    }

    fileprivate var acceptHeader: String {
        switch self {
        case .page:
            "text/html, application/xhtml+xml"
        case .image:
            "image/*"
        }
    }

    fileprivate func accepts(mimeType: String) -> Bool {
        switch self {
        case .page:
            mimeType == "text/html" || mimeType == "application/xhtml+xml"
        case .image:
            mimeType.hasPrefix("image/")
        }
    }
}

struct LinkMetadataResponse: Sendable {
    let data: Data
    let finalURL: URL
    let mimeType: String
}

struct LinkMetadataTransportResponse: Sendable {
    let responseURL: URL
    let statusCode: Int
    let mimeType: String?
    let location: String?
    let body: Data
}

protocol LinkMetadataHTTPTransport: Sendable {
    func load(
        _ request: URLRequest,
        maximumBodyBytes: Int
    ) async throws -> LinkMetadataTransportResponse
}

protocol LinkMetadataHTTPFetching: Sendable {
    func fetch(
        _ url: URL,
        as kind: LinkMetadataResourceKind
    ) async throws -> LinkMetadataResponse
}

enum LinkMetadataHTTPClientError: Error, Equatable {
    case automaticEnrichmentDisabled
    case blockedDestination
    case invalidRedirect
    case tooManyRedirects
    case unacceptableStatus(Int)
    case unacceptableMIMEType
    case invalidResponse
    case bodyTooLarge
    case deadlineExceeded
}

struct LinkMetadataHTTPClient: LinkMetadataHTTPFetching {
    typealias Sleeper = @Sendable (UInt64) async throws -> Void

    private static let redirectStatusCodes = Set([301, 302, 303, 307, 308])
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X) ClipEase/1.0"

    private let policy: LinkMetadataNetworkPolicy
    private let transport: any LinkMetadataHTTPTransport
    private let maximumRedirectCount: Int
    private let deadlineNanoseconds: UInt64
    private let automaticEnrichmentEnabled: @Sendable () -> Bool
    private let sleeper: Sleeper

    init(
        policy: LinkMetadataNetworkPolicy,
        transport: any LinkMetadataHTTPTransport,
        maximumRedirectCount: Int = 5,
        deadlineNanoseconds: UInt64 = 4_000_000_000,
        automaticEnrichmentEnabled: @escaping @Sendable () -> Bool = { true },
        sleeper: @escaping Sleeper = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.policy = policy
        self.transport = transport
        self.maximumRedirectCount = max(0, maximumRedirectCount)
        self.deadlineNanoseconds = deadlineNanoseconds
        self.automaticEnrichmentEnabled = automaticEnrichmentEnabled
        self.sleeper = sleeper
    }

    func fetch(
        _ url: URL,
        as kind: LinkMetadataResourceKind
    ) async throws -> LinkMetadataResponse {
        guard automaticEnrichmentEnabled() else {
            throw LinkMetadataHTTPClientError.automaticEnrichmentDisabled
        }

        return try await withThrowingTaskGroup(of: LinkMetadataResponse.self) { group in
            group.addTask {
                try await fetchFollowingRedirects(url, as: kind)
            }
            group.addTask {
                try await sleeper(deadlineNanoseconds)
                try Task.checkCancellation()
                throw LinkMetadataHTTPClientError.deadlineExceeded
            }
            defer { group.cancelAll() }

            guard let response = try await group.next() else {
                throw LinkMetadataHTTPClientError.invalidResponse
            }
            return response
        }
    }

    private func fetchFollowingRedirects(
        _ initialURL: URL,
        as kind: LinkMetadataResourceKind
    ) async throws -> LinkMetadataResponse {
        var currentURL = initialURL
        var redirectCount = 0

        while true {
            try Task.checkCancellation()
            guard automaticEnrichmentEnabled() else {
                throw LinkMetadataHTTPClientError.automaticEnrichmentDisabled
            }
            guard await policy.allows(currentURL) else {
                throw LinkMetadataHTTPClientError.blockedDestination
            }

            let response = try await transport.load(
                Self.request(for: currentURL, kind: kind),
                maximumBodyBytes: kind.maximumBodyBytes
            )
            guard response.body.count <= kind.maximumBodyBytes else {
                throw LinkMetadataHTTPClientError.bodyTooLarge
            }
            guard await policy.allows(response.responseURL) else {
                throw LinkMetadataHTTPClientError.blockedDestination
            }

            if Self.redirectStatusCodes.contains(response.statusCode) {
                guard redirectCount < maximumRedirectCount else {
                    throw LinkMetadataHTTPClientError.tooManyRedirects
                }
                guard let location = response.location,
                      let redirectURL = URL(
                        string: location,
                        relativeTo: response.responseURL
                      )?.absoluteURL else {
                    throw LinkMetadataHTTPClientError.invalidRedirect
                }
                redirectCount += 1
                currentURL = redirectURL
                continue
            }

            guard (200...299).contains(response.statusCode) else {
                throw LinkMetadataHTTPClientError.unacceptableStatus(response.statusCode)
            }
            guard let mimeType = Self.normalizedMIMEType(response.mimeType),
                  kind.accepts(mimeType: mimeType) else {
                throw LinkMetadataHTTPClientError.unacceptableMIMEType
            }

            return LinkMetadataResponse(
                data: response.body,
                finalURL: response.responseURL,
                mimeType: mimeType
            )
        }
    }

    private static func request(
        for url: URL,
        kind: LinkMetadataResourceKind
    ) -> URLRequest {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 4
        )
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(kind.acceptHeader, forHTTPHeaderField: "Accept")
        return request
    }

    private static func normalizedMIMEType(_ rawValue: String?) -> String? {
        rawValue?
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    static func live() -> LinkMetadataHTTPClient {
        LinkMetadataHTTPClient(
            policy: LinkMetadataNetworkPolicy(
                resolver: SystemLinkMetadataAddressResolver()
            ),
            transport: URLSessionLinkMetadataHTTPTransport(),
            automaticEnrichmentEnabled: LinkMetadataAutomaticEnrichment.isEnabled
        )
    }
}

enum LinkMetadataAutomaticEnrichment {
    private static let processAllowsEnrichment: Bool = {
        let value = ProcessInfo.processInfo.environment[
            "CLIPEASE_DISABLE_AUTOMATIC_LINK_METADATA"
        ]?.lowercased()
        return value != "1" && value != "true" && value != "yes"
    }()

    static func isEnabled() -> Bool {
        processAllowsEnrichment
    }
}
