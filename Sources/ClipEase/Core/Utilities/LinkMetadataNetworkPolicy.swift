import Darwin
import Foundation

protocol LinkMetadataAddressResolving: Sendable {
    func addresses(for host: String) async throws -> [LinkMetadataIPAddress]
}

struct LinkMetadataIPAddress: Hashable, Sendable {
    enum Family: Hashable, Sendable {
        case ipv4
        case ipv6
    }

    let family: Family
    let bytes: [UInt8]
}

struct LinkMetadataNetworkPolicy: Sendable {
    private let resolver: any LinkMetadataAddressResolving

    init(resolver: any LinkMetadataAddressResolving) {
        self.resolver = resolver
    }

    /// DNS preflight is defense in depth. Resolution can change before a
    /// connection is established, so callers must repeat this check per hop;
    /// this policy does not eliminate DNS-rebinding TOCTOU.
    func allows(_ url: URL) async -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.user == nil,
              url.password == nil,
              let rawHost = url.host(percentEncoded: false),
              let host = Self.normalizedHost(rawHost),
              !Self.isLocalHostName(host) else {
            return false
        }

        if let address = Self.parseIPAddress(host) {
            return Self.isGlobalUnicast(address)
        }

        // A colon denotes an IPv6-looking literal. Never pass a malformed
        // literal to name resolution where platform-specific parsing may vary.
        guard !host.contains(":") else {
            return false
        }

        do {
            let addresses = try await resolver.addresses(for: host)
            return !addresses.isEmpty && addresses.allSatisfy(Self.isGlobalUnicast)
        } catch {
            return false
        }
    }

    static func isGlobalUnicast(_ address: LinkMetadataIPAddress) -> Bool {
        switch address.family {
        case .ipv4:
            isGlobalUnicastIPv4(address.bytes)
        case .ipv6:
            isGlobalUnicastIPv6(address.bytes)
        }
    }

    private static func normalizedHost(_ rawHost: String) -> String? {
        var host = rawHost.lowercased()
        if host.hasPrefix("[") && host.hasSuffix("]") {
            host.removeFirst()
            host.removeLast()
        }
        while host.hasSuffix(".") {
            host.removeLast()
        }
        return host.isEmpty ? nil : host
    }

    private static func isLocalHostName(_ host: String) -> Bool {
        host == "localhost"
            || host.hasSuffix(".localhost")
            || host == "local"
            || host.hasSuffix(".local")
            || host == "home.arpa"
            || host.hasSuffix(".home.arpa")
    }

    private static func parseIPAddress(_ host: String) -> LinkMetadataIPAddress? {
        var ipv4Address = in_addr()
        if host.withCString({ inet_pton(AF_INET, $0, &ipv4Address) }) == 1 {
            return LinkMetadataIPAddress(
                family: .ipv4,
                bytes: withUnsafeBytes(of: &ipv4Address) { Array($0) }
            )
        }

        var ipv6Address = in6_addr()
        if host.withCString({ inet_pton(AF_INET6, $0, &ipv6Address) }) == 1 {
            return LinkMetadataIPAddress(
                family: .ipv6,
                bytes: withUnsafeBytes(of: &ipv6Address) { Array($0) }
            )
        }

        return nil
    }

    private static func isGlobalUnicastIPv4(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 4 else {
            return false
        }

        let blockedRanges: [([UInt8], Int)] = [
            ([0, 0, 0, 0], 8),
            ([10, 0, 0, 0], 8),
            ([100, 64, 0, 0], 10),
            ([127, 0, 0, 0], 8),
            ([169, 254, 0, 0], 16),
            ([172, 16, 0, 0], 12),
            ([192, 0, 0, 0], 24),
            ([192, 0, 2, 0], 24),
            ([192, 31, 196, 0], 24),
            ([192, 52, 193, 0], 24),
            ([192, 88, 99, 0], 24),
            ([192, 168, 0, 0], 16),
            ([192, 175, 48, 0], 24),
            ([198, 18, 0, 0], 15),
            ([198, 51, 100, 0], 24),
            ([203, 0, 113, 0], 24),
            ([224, 0, 0, 0], 4),
            ([240, 0, 0, 0], 4)
        ]

        return !blockedRanges.contains { prefix, bitCount in
            matchesPrefix(bytes, prefix: prefix, bitCount: bitCount)
        }
    }

    private static func isGlobalUnicastIPv6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else {
            return false
        }

        let ipv4MappedPrefix = Array(repeating: UInt8(0), count: 10) + [0xFF, 0xFF]
        if Array(bytes.prefix(12)) == ipv4MappedPrefix {
            return isGlobalUnicastIPv4(Array(bytes.suffix(4)))
        }

        // Currently allocated IPv6 global unicast space is 2000::/3.
        guard bytes[0] & 0xE0 == 0x20 else {
            return false
        }

        let blockedRanges: [([UInt8], Int)] = [
            ([0x20, 0x01, 0x00], 23),
            ([0x20, 0x01, 0x0D, 0xB8], 32),
            ([0x20, 0x02], 16),
            ([0x26, 0x20, 0x00, 0x4F, 0x80, 0x00], 48),
            ([0x3F, 0xFE], 16),
            ([0x3F, 0xFF, 0x00], 20)
        ]

        return !blockedRanges.contains { prefix, bitCount in
            matchesPrefix(bytes, prefix: prefix, bitCount: bitCount)
        }
    }

    private static func matchesPrefix(
        _ address: [UInt8],
        prefix: [UInt8],
        bitCount: Int
    ) -> Bool {
        let completeBytes = bitCount / 8
        let remainingBits = bitCount % 8
        guard address.count >= completeBytes + (remainingBits == 0 ? 0 : 1),
              prefix.count >= completeBytes + (remainingBits == 0 ? 0 : 1),
              Array(address.prefix(completeBytes)) == Array(prefix.prefix(completeBytes)) else {
            return false
        }

        guard remainingBits > 0 else {
            return true
        }

        let mask = UInt8.max << (8 - remainingBits)
        return address[completeBytes] & mask == prefix[completeBytes] & mask
    }
}

struct SystemLinkMetadataAddressResolver: LinkMetadataAddressResolving {
    private static let coordinator = LinkMetadataAddressResolutionCoordinator(
        maximumConcurrentResolutions: 2,
        cacheTTL: 2,
        resolver: { host in
            try Self.resolve(host: host)
        }
    )

    func addresses(for host: String) async throws -> [LinkMetadataIPAddress] {
        try await Self.coordinator.addresses(for: host)
    }

    fileprivate static func resolve(host: String) throws -> [LinkMetadataIPAddress] {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &result)
        guard status == 0 else {
            throw LinkMetadataAddressResolutionError(status: status)
        }
        defer { freeaddrinfo(result) }

        var addresses: Set<LinkMetadataIPAddress> = []
        var cursor = result
        while let info = cursor?.pointee {
            if info.ai_family == AF_INET,
               let socketAddress = info.ai_addr {
                var address = socketAddress
                    .withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                addresses.insert(
                    LinkMetadataIPAddress(
                        family: .ipv4,
                        bytes: withUnsafeBytes(of: &address) { Array($0) }
                    )
                )
            } else if info.ai_family == AF_INET6,
                      let socketAddress = info.ai_addr {
                var address = socketAddress
                    .withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
                addresses.insert(
                    LinkMetadataIPAddress(
                        family: .ipv6,
                        bytes: withUnsafeBytes(of: &address) { Array($0) }
                    )
                )
            }
            cursor = info.ai_next
        }

        return Array(addresses)
    }
}

final class LinkMetadataAddressResolutionCoordinator: @unchecked Sendable {
    typealias Resolver = @Sendable (String) throws -> [LinkMetadataIPAddress]

    private struct CacheEntry {
        let addresses: [LinkMetadataIPAddress]
        let expiresAt: Date
    }

    private final class Work: @unchecked Sendable {
        let id: UUID
        let operation: BlockOperation
        var waiters: [UUID: LinkMetadataAddressResolutionDriver]

        init(
            id: UUID,
            operation: BlockOperation,
            waiterID: UUID,
            driver: LinkMetadataAddressResolutionDriver
        ) {
            self.id = id
            self.operation = operation
            self.waiters = [waiterID: driver]
        }
    }

    private let queue: OperationQueue
    private let cacheTTL: TimeInterval
    private let maximumCacheEntries: Int
    private let now: @Sendable () -> Date
    private let resolver: Resolver
    private let lock = NSLock()
    private var cacheByHost: [String: CacheEntry] = [:]
    private var workByHost: [String: Work] = [:]
    private var cancelledWaiterIDs = Set<UUID>()

    init(
        maximumConcurrentResolutions: Int,
        cacheTTL: TimeInterval,
        maximumCacheEntries: Int = 128,
        now: @escaping @Sendable () -> Date = Date.init,
        resolver: @escaping Resolver
    ) {
        let queue = OperationQueue()
        queue.name = "com.clipease.link-metadata-dns"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = max(1, maximumConcurrentResolutions)
        self.queue = queue
        self.cacheTTL = max(0, cacheTTL)
        self.maximumCacheEntries = max(1, maximumCacheEntries)
        self.now = now
        self.resolver = resolver
    }

    var pendingResolutionCount: Int {
        lock.withLock { workByHost.count }
    }

    var cachedHostCount: Int {
        lock.withLock { cacheByHost.count }
    }

    func pendingWaiterCount(for host: String) -> Int {
        lock.withLock { workByHost[host]?.waiters.count ?? 0 }
    }

    func addresses(for host: String) async throws -> [LinkMetadataIPAddress] {
        let waiterID = UUID()
        let driver = LinkMetadataAddressResolutionDriver()

        do {
            let addresses = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    guard driver.install(continuation) else {
                        return
                    }
                    register(driver, waiterID: waiterID, host: host)
                }
            } onCancel: {
                driver.cancel()
                cancel(waiterID: waiterID, host: host)
            }
            clearCancellationMarker(waiterID)
            return addresses
        } catch {
            clearCancellationMarker(waiterID)
            throw error
        }
    }

    private func register(
        _ driver: LinkMetadataAddressResolutionDriver,
        waiterID: UUID,
        host: String
    ) {
        var cachedAddresses: [LinkMetadataIPAddress]?
        var operationToStart: BlockOperation?
        let now = self.now()

        lock.withLock {
            guard cancelledWaiterIDs.remove(waiterID) == nil else {
                return
            }

            pruneCacheLocked(at: now)
            if let entry = cacheByHost[host], entry.expiresAt > now {
                cachedAddresses = entry.addresses
                return
            }

            if let work = workByHost[host] {
                work.waiters[waiterID] = driver
                return
            }

            let workID = UUID()
            let resolver = self.resolver
            let operation = BlockOperation { [weak self] in
                let result = Result { try resolver(host) }
                self?.complete(host: host, workID: workID, result: result)
            }
            workByHost[host] = Work(
                id: workID,
                operation: operation,
                waiterID: waiterID,
                driver: driver
            )
            operationToStart = operation
        }

        if let cachedAddresses {
            driver.finish(.success(cachedAddresses))
        } else if let operationToStart {
            queue.addOperation(operationToStart)
        }
    }

    private func cancel(waiterID: UUID, host: String) {
        var operationToCancel: BlockOperation?
        lock.withLock {
            guard let work = workByHost[host] else {
                cancelledWaiterIDs.insert(waiterID)
                return
            }
            guard work.waiters.removeValue(forKey: waiterID) != nil else {
                return
            }
            if work.waiters.isEmpty {
                workByHost[host] = nil
                operationToCancel = work.operation
            }
        }
        operationToCancel?.cancel()
    }

    private func complete(
        host: String,
        workID: UUID,
        result: Result<[LinkMetadataIPAddress], Error>
    ) {
        var drivers: [LinkMetadataAddressResolutionDriver] = []
        let now = self.now()
        lock.withLock {
            guard let work = workByHost[host], work.id == workID else {
                return
            }
            workByHost[host] = nil
            pruneCacheLocked(at: now)
            if case .success(let addresses) = result, cacheTTL > 0 {
                cacheByHost[host] = CacheEntry(
                    addresses: addresses,
                    expiresAt: now.addingTimeInterval(cacheTTL)
                )
                pruneCacheLocked(at: now)
            }
            drivers = Array(work.waiters.values)
        }
        drivers.forEach { $0.finish(result) }
    }

    private func clearCancellationMarker(_ waiterID: UUID) {
        _ = lock.withLock { cancelledWaiterIDs.remove(waiterID) }
    }

    private func pruneCacheLocked(at date: Date) {
        cacheByHost = cacheByHost.filter { $0.value.expiresAt > date }
        let overflow = cacheByHost.count - maximumCacheEntries
        guard overflow > 0 else {
            return
        }
        let keysToRemove = cacheByHost
            .sorted { $0.value.expiresAt < $1.value.expiresAt }
            .prefix(overflow)
            .map(\.key)
        keysToRemove.forEach { cacheByHost[$0] = nil }
    }
}

private struct LinkMetadataAddressResolutionError: Error {
    let status: Int32
}

private final class LinkMetadataAddressResolutionDriver: @unchecked Sendable {
    typealias Continuation = CheckedContinuation<[LinkMetadataIPAddress], Error>

    private let lock = NSLock()
    private var continuation: Continuation?
    private var terminalResult: Result<[LinkMetadataIPAddress], Error>?

    func install(_ continuation: Continuation) -> Bool {
        let result = lock.withLock { () -> Result<[LinkMetadataIPAddress], Error>? in
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

    func finish(_ result: Result<[LinkMetadataIPAddress], Error>) {
        complete(with: result)
    }

    func cancel() {
        complete(with: .failure(CancellationError()))
    }

    private func complete(with result: Result<[LinkMetadataIPAddress], Error>) {
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
    }
}
