import Foundation

enum LinkMetadataHTTPTransportError: Error, Equatable {
    case bodyTooLarge
    case invalidResponse
}

final class URLSessionLinkMetadataHTTPTransport: LinkMetadataHTTPTransport, @unchecked Sendable {
    private let delegate: LinkMetadataURLSessionDelegate
    private let session: URLSession

    init(
        configuration: URLSessionConfiguration = URLSessionLinkMetadataHTTPTransport.makeConfiguration()
    ) {
        let delegate = LinkMetadataURLSessionDelegate()
        self.delegate = delegate
        self.session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
    }

    deinit {
        session.invalidateAndCancel()
    }

    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 4
        configuration.waitsForConnectivity = false
        return configuration
    }

    func load(
        _ request: URLRequest,
        maximumBodyBytes: Int
    ) async throws -> LinkMetadataTransportResponse {
        guard maximumBodyBytes >= 0 else {
            throw LinkMetadataHTTPTransportError.bodyTooLarge
        }

        let task = session.dataTask(with: request)
        let driver = LinkMetadataURLSessionRequestDriver(
            task: task,
            maximumBodyBytes: maximumBodyBytes,
            onTerminal: { [weak delegate] in
                delegate?.removeDriver(for: task.taskIdentifier)
            }
        )
        delegate.register(driver, for: task.taskIdentifier)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if driver.install(continuation) {
                    task.resume()
                }
            }
        } onCancel: {
            driver.cancel()
        }
    }
}

private final class LinkMetadataURLSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var drivers: [Int: LinkMetadataURLSessionRequestDriver] = [:]

    func register(
        _ driver: LinkMetadataURLSessionRequestDriver,
        for taskIdentifier: Int
    ) {
        lock.withLock { drivers[taskIdentifier] = driver }
    }

    func removeDriver(for taskIdentifier: Int) {
        _ = lock.withLock { drivers.removeValue(forKey: taskIdentifier) }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let driver = driver(for: dataTask.taskIdentifier) else {
            completionHandler(.cancel)
            return
        }
        completionHandler(driver.receive(response: response))
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        driver(for: dataTask.taskIdentifier)?.receive(data: data)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        driver(for: task.taskIdentifier)?.complete(with: error)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        driver(for: task.taskIdentifier)?.completeRedirect(response)
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completeAuthenticationChallenge(challenge, completionHandler: completionHandler)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completeAuthenticationChallenge(challenge, completionHandler: completionHandler)
    }

    private func driver(for taskIdentifier: Int) -> LinkMetadataURLSessionRequestDriver? {
        lock.withLock { drivers[taskIdentifier] }
    }

    private func completeAuthenticationChallenge(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

private final class LinkMetadataURLSessionRequestDriver: @unchecked Sendable {
    typealias Continuation = CheckedContinuation<LinkMetadataTransportResponse, Error>

    private struct ResponseSnapshot {
        let url: URL
        let statusCode: Int
        let mimeType: String?
        let location: String?
    }

    private let task: URLSessionDataTask
    private let maximumBodyBytes: Int
    private let onTerminal: @Sendable () -> Void
    private let lock = NSLock()

    private var continuation: Continuation?
    private var terminalResult: Result<LinkMetadataTransportResponse, Error>?
    private var response: ResponseSnapshot?
    private var body = Data()

    init(
        task: URLSessionDataTask,
        maximumBodyBytes: Int,
        onTerminal: @escaping @Sendable () -> Void
    ) {
        self.task = task
        self.maximumBodyBytes = maximumBodyBytes
        self.onTerminal = onTerminal
    }

    func install(_ continuation: Continuation) -> Bool {
        let result = lock.withLock { () -> Result<LinkMetadataTransportResponse, Error>? in
            if let terminalResult {
                return terminalResult
            }
            self.continuation = continuation
            return nil
        }

        if let result {
            continuation.resume(with: result)
            return false
        }
        return true
    }

    func receive(response urlResponse: URLResponse) -> URLSession.ResponseDisposition {
        guard let httpResponse = urlResponse as? HTTPURLResponse,
              let responseURL = httpResponse.url else {
            finish(.failure(LinkMetadataHTTPTransportError.invalidResponse))
            task.cancel()
            return .cancel
        }

        if httpResponse.expectedContentLength > Int64(maximumBodyBytes) {
            finish(.failure(LinkMetadataHTTPTransportError.bodyTooLarge))
            task.cancel()
            return .cancel
        }

        lock.withLock {
            guard terminalResult == nil else {
                return
            }
            response = ResponseSnapshot(
                url: responseURL,
                statusCode: httpResponse.statusCode,
                mimeType: httpResponse.mimeType,
                location: httpResponse.value(forHTTPHeaderField: "Location")
            )
            if httpResponse.expectedContentLength > 0 {
                body.reserveCapacity(Int(httpResponse.expectedContentLength))
            }
        }
        return .allow
    }

    func receive(data: Data) {
        let exceededLimit = lock.withLock { () -> Bool in
            guard terminalResult == nil else {
                return false
            }
            guard data.count <= maximumBodyBytes - body.count else {
                return true
            }
            body.append(data)
            return false
        }

        if exceededLimit {
            finish(.failure(LinkMetadataHTTPTransportError.bodyTooLarge))
            task.cancel()
        }
    }

    func completeRedirect(_ response: HTTPURLResponse) {
        guard let responseURL = response.url else {
            finish(.failure(LinkMetadataHTTPTransportError.invalidResponse))
            task.cancel()
            return
        }

        finish(
            .success(
                LinkMetadataTransportResponse(
                    responseURL: responseURL,
                    statusCode: response.statusCode,
                    mimeType: response.mimeType,
                    location: response.value(forHTTPHeaderField: "Location"),
                    body: Data()
                )
            )
        )
        task.cancel()
    }

    func complete(with error: (any Error)?) {
        if let error {
            finish(.failure(error))
            return
        }

        let result = lock.withLock { () -> Result<LinkMetadataTransportResponse, Error> in
            guard let response else {
                return .failure(LinkMetadataHTTPTransportError.invalidResponse)
            }
            return .success(
                LinkMetadataTransportResponse(
                    responseURL: response.url,
                    statusCode: response.statusCode,
                    mimeType: response.mimeType,
                    location: response.location,
                    body: body
                )
            )
        }
        finish(result)
    }

    func cancel() {
        finish(.failure(CancellationError()))
        task.cancel()
    }

    private func finish(_ result: Result<LinkMetadataTransportResponse, Error>) {
        let completion = lock.withLock { () -> (Continuation?, Bool) in
            guard terminalResult == nil else {
                return (nil, false)
            }
            terminalResult = result
            let continuation = self.continuation
            self.continuation = nil
            return (continuation, true)
        }

        guard completion.1 else {
            return
        }
        completion.0?.resume(with: result)
        onTerminal()
    }
}
