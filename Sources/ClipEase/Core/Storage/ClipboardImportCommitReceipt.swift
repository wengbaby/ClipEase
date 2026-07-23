import Foundation

final class ClipboardImportAuthority: @unchecked Sendable {
    private enum State: Equatable {
        case current
        case invalidated
        case accepted
    }

    private let lock = NSLock()
    private var state = State.current

    var isCurrent: Bool {
        lock.withLock { state == .current }
    }

    func invalidate() {
        lock.withLock {
            guard state == .current else { return }
            state = .invalidated
        }
    }

    func tryAccept() -> Bool {
        lock.withLock {
            guard state == .current else { return false }
            state = .accepted
            return true
        }
    }
}

struct ClipboardImportCommitReceipt: @unchecked Sendable {
    let revision: Int
    let insertedItem: ClipboardItem
    let displacedItems: [ClipboardItem]
    let acceptedCleanup: ClipboardAttachmentCleanup
    let stagedReservations: [ClipboardAttachmentReservation]
    fileprivate let resolution = ClipboardImportReceiptResolution()
}

private final class ClipboardImportReceiptResolution: @unchecked Sendable {
    enum Decision {
        case accepted
        case compensated
    }

    private let lock = NSLock()
    private var decision: Decision?

    func resolve(_ decision: Decision) -> Bool {
        lock.withLock {
            guard self.decision == nil else { return false }
            self.decision = decision
            return true
        }
    }
}

extension ClipboardImportCommitReceipt {
    func resolveAccepted() -> Bool {
        resolution.resolve(.accepted)
    }

    func resolveCompensated() -> Bool {
        resolution.resolve(.compensated)
    }
}
