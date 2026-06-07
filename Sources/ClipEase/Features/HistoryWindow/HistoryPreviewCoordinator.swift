import Foundation

@MainActor
final class HistoryPreviewCoordinator: ObservableObject {
    private let retryDelaysNanoseconds: [UInt64]
    private var followTask: Task<Void, Never>?
    private(set) var pendingFollowItemID: ClipboardItem.ID?

    init(retryDelaysNanoseconds: [UInt64] = HistoryPreviewFollowPolicy.retryDelaysNanoseconds) {
        self.retryDelaysNanoseconds = retryDelaysNanoseconds
    }

    func cancelFollow() {
        followTask?.cancel()
        followTask = nil
        pendingFollowItemID = nil
    }

    func markNeedsFollow(_ itemID: ClipboardItem.ID) {
        pendingFollowItemID = itemID
    }

    func scheduleFollow(
        itemID: ClipboardItem.ID,
        isPreviewVisible: @escaping @MainActor () -> Bool,
        currentPreviewItemID: @escaping @MainActor () -> ClipboardItem.ID?,
        frameForItem: @escaping @MainActor (ClipboardItem.ID) -> CGRect?,
        onMovePreview: @escaping @MainActor (CGRect) -> Void
    ) {
        pendingFollowItemID = itemID
        guard followTask == nil else {
            return
        }

        followTask = Task { @MainActor in
            var targetID = itemID
            for delay in retryDelaysNanoseconds {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else {
                    return
                }

                targetID = pendingFollowItemID ?? targetID
                guard isPreviewVisible(),
                      currentPreviewItemID() == targetID,
                      let refreshedFrame = frameForItem(targetID) else {
                    continue
                }

                onMovePreview(refreshedFrame)
            }

            pendingFollowItemID = nil
            followTask = nil
        }
    }
}
