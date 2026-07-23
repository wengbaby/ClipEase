import Foundation

enum ClipboardAttachmentKind: Hashable, Sendable {
    case image
    case richText
}

struct ClipboardAttachmentReservationRegistryDiagnostics: Equatable, Sendable {
    let trackedKeyCount: Int
    let idleKeyCount: Int
}

private struct ClipboardAttachmentReservationKey: Hashable, Sendable {
    let kind: ClipboardAttachmentKind
    let fileName: String
}

final class ClipboardAttachmentReservation: @unchecked Sendable {
    let candidates: ClipboardAttachmentCleanup

    private let registry: ClipboardAttachmentReservationRegistry
    private let leases: [ClipboardAttachmentReservationRegistry.StateLease]
    private let lock = NSLock()
    private var isReleased = false

    fileprivate init(
        candidates: ClipboardAttachmentCleanup,
        registry: ClipboardAttachmentReservationRegistry,
        leases: [ClipboardAttachmentReservationRegistry.StateLease]
    ) {
        self.candidates = candidates
        self.registry = registry
        self.leases = leases
    }

    func release() {
        let shouldRelease = lock.withLock {
            guard !isReleased else {
                return false
            }
            isReleased = true
            return true
        }
        guard shouldRelease else {
            return
        }
        registry.release(leases)
    }

    deinit {
        release()
    }
}

final class ClipboardAttachmentDeletionClaim: @unchecked Sendable {
    let candidates: ClipboardAttachmentCleanup

    private let registry: ClipboardAttachmentReservationRegistry
    private let leases: [ClipboardAttachmentReservationRegistry.StateLease]
    private let lock = NSLock()
    private var isCompleted = false

    fileprivate init(
        candidates: ClipboardAttachmentCleanup,
        registry: ClipboardAttachmentReservationRegistry,
        leases: [ClipboardAttachmentReservationRegistry.StateLease]
    ) {
        self.candidates = candidates
        self.registry = registry
        self.leases = leases
    }

    func complete() {
        let shouldComplete = lock.withLock {
            guard !isCompleted else {
                return false
            }
            isCompleted = true
            return true
        }
        guard shouldComplete else {
            return
        }
        registry.completeDeletionClaim(leases)
    }

    deinit {
        complete()
    }
}

final class ClipboardAttachmentReservationRegistry: @unchecked Sendable {
    fileprivate final class KeyState: @unchecked Sendable {
        var reservationCount = 0
        var isDeleting = false
        var waitingReservationCount = 0
    }

    fileprivate struct StateLease {
        let key: ClipboardAttachmentReservationKey
        let state: KeyState
    }

    private let condition = NSCondition()
    private var states: [ClipboardAttachmentReservationKey: KeyState] = [:]
    private let onReservationBlockedByDeletion: @Sendable (ClipboardAttachmentCleanup) -> Void

    init(
        onReservationBlockedByDeletion: @escaping @Sendable (ClipboardAttachmentCleanup) -> Void = { _ in }
    ) {
        self.onReservationBlockedByDeletion = onReservationBlockedByDeletion
    }

    func reserve(_ candidates: ClipboardAttachmentCleanup) -> ClipboardAttachmentReservation? {
        guard !candidates.isEmpty else {
            return nil
        }

        var leases: [StateLease] = []
        for key in keys(for: candidates) {
            condition.lock()
            let state = stateLocked(for: key)
            if state.isDeleting {
                state.waitingReservationCount += 1
                condition.unlock()
                onReservationBlockedByDeletion(cleanup(for: key))
                condition.lock()
                while state.isDeleting {
                    condition.wait()
                }
                state.waitingReservationCount -= 1
            }
            state.reservationCount += 1
            leases.append(StateLease(key: key, state: state))
            condition.unlock()
        }

        return ClipboardAttachmentReservation(
            candidates: candidates,
            registry: self,
            leases: leases
        )
    }

    func subtractingActiveReservations(
        from candidates: ClipboardAttachmentCleanup
    ) -> ClipboardAttachmentCleanup {
        condition.lock()
        let unreserved = ClipboardAttachmentCleanup(
            imageFileNames: candidates.imageFileNames.filter { isUnreservedLocked($0, kind: .image) },
            richTextFileNames: candidates.richTextFileNames.filter { isUnreservedLocked($0, kind: .richText) }
        )
        condition.unlock()
        return unreserved
    }

    func claimDeletion(
        for candidates: ClipboardAttachmentCleanup
    ) -> ClipboardAttachmentDeletionClaim? {
        condition.lock()
        var imageFileNames = Set<String>()
        var richTextFileNames = Set<String>()
        var leases: [StateLease] = []

        for key in keys(for: candidates) {
            let state = stateLocked(for: key)
            guard state.reservationCount == 0,
                  !state.isDeleting,
                  state.waitingReservationCount == 0 else {
                evictIfIdleLocked(key, state: state)
                continue
            }

            state.isDeleting = true
            leases.append(StateLease(key: key, state: state))
            switch key.kind {
            case .image:
                imageFileNames.insert(key.fileName)
            case .richText:
                richTextFileNames.insert(key.fileName)
            }
        }
        condition.unlock()

        let claimed = ClipboardAttachmentCleanup(
            imageFileNames: imageFileNames,
            richTextFileNames: richTextFileNames
        )
        guard !claimed.isEmpty else {
            return nil
        }
        return ClipboardAttachmentDeletionClaim(
            candidates: claimed,
            registry: self,
            leases: leases
        )
    }

    func diagnosticsForTesting() -> ClipboardAttachmentReservationRegistryDiagnostics {
        condition.lock()
        let idleKeyCount = states.values.reduce(into: 0) { count, state in
            if state.reservationCount == 0,
               !state.isDeleting,
               state.waitingReservationCount == 0 {
                count += 1
            }
        }
        let diagnostics = ClipboardAttachmentReservationRegistryDiagnostics(
            trackedKeyCount: states.count,
            idleKeyCount: idleKeyCount
        )
        condition.unlock()
        return diagnostics
    }

    fileprivate func release(_ leases: [StateLease]) {
        condition.lock()
        for lease in leases where isCurrentLocked(lease) {
            lease.state.reservationCount = max(0, lease.state.reservationCount - 1)
            evictIfIdleLocked(lease.key, state: lease.state)
        }
        condition.unlock()
    }

    fileprivate func completeDeletionClaim(_ leases: [StateLease]) {
        condition.lock()
        for lease in leases where isCurrentLocked(lease) {
            lease.state.isDeleting = false
            evictIfIdleLocked(lease.key, state: lease.state)
        }
        condition.broadcast()
        condition.unlock()
    }

    private func stateLocked(for key: ClipboardAttachmentReservationKey) -> KeyState {
        if let state = states[key] {
            return state
        }
        let state = KeyState()
        states[key] = state
        return state
    }

    private func isUnreservedLocked(_ fileName: String, kind: ClipboardAttachmentKind) -> Bool {
        guard let state = states[ClipboardAttachmentReservationKey(kind: kind, fileName: fileName)] else {
            return true
        }
        return state.reservationCount == 0 && !state.isDeleting
    }

    private func isCurrentLocked(_ lease: StateLease) -> Bool {
        states[lease.key] === lease.state
    }

    private func evictIfIdleLocked(
        _ key: ClipboardAttachmentReservationKey,
        state: KeyState
    ) {
        guard state.reservationCount == 0,
              !state.isDeleting,
              state.waitingReservationCount == 0,
              states[key] === state else {
            return
        }
        states.removeValue(forKey: key)
    }

    private func keys(for candidates: ClipboardAttachmentCleanup) -> [ClipboardAttachmentReservationKey] {
        candidates.imageFileNames.map {
            ClipboardAttachmentReservationKey(kind: .image, fileName: $0)
        } + candidates.richTextFileNames.map {
            ClipboardAttachmentReservationKey(kind: .richText, fileName: $0)
        }
    }

    private func cleanup(for key: ClipboardAttachmentReservationKey) -> ClipboardAttachmentCleanup {
        switch key.kind {
        case .image:
            ClipboardAttachmentCleanup(imageFileNames: [key.fileName])
        case .richText:
            ClipboardAttachmentCleanup(richTextFileNames: [key.fileName])
        }
    }
}
