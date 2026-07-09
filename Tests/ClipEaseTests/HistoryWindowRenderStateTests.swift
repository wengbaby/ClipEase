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

@MainActor
@Test func renderStateFrameDiagnosticsMarkDoesNotPublishViewInvalidation() {
    let state = HistoryWindowRenderState()
    var didPublish = false
    let cancellable = state.objectWillChange.sink {
        didPublish = true
    }

    state.prepareForShow(itemCount: 12)
    state.mark("panel-target-frame-applying", metadata: ["deltaY": "-360.0"])

    #expect(!didPublish)
    _ = cancellable
}
