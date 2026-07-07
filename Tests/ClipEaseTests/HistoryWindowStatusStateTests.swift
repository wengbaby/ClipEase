import Foundation
import Testing
@testable import ClipEase

@Test func statusStateShowAdvancesGenerationAndStoresText() {
    var state = HistoryWindowStatusState()

    let firstGeneration = state.show("已复制")
    let secondGeneration = state.show("已粘贴")

    #expect(firstGeneration == 1)
    #expect(secondGeneration == 2)
    #expect(state.text == "已粘贴")
    #expect(state.generation == 2)
}

@Test func statusStateClearsOnlyMatchingGeneration() {
    var state = HistoryWindowStatusState()

    let oldGeneration = state.show("旧状态")
    let latestGeneration = state.show("新状态")

    let didClearOldGeneration = state.clearIfCurrent(generation: oldGeneration)
    #expect(!didClearOldGeneration)
    #expect(state.text == "新状态")

    let didClearLatestGeneration = state.clearIfCurrent(generation: latestGeneration)
    #expect(didClearLatestGeneration)
    #expect(state.text == nil)
}
