import Testing
@testable import ClipEase

@MainActor
@Test func renderStatePrepareForShowDoesNotPublishViewInvalidation() {
    let state = HistoryWindowRenderState()
    var didPublish = false
    let cancellable = state.objectWillChange.sink {
        didPublish = true
    }

    state.prepareForShow(itemCount: 12)

    #expect(!didPublish)
    _ = cancellable
}
