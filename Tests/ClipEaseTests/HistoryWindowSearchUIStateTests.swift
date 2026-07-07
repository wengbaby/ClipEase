import Testing
@testable import ClipEase

@Test func searchUIStateClearsTextWithoutDroppingFilters() {
    var state = HistoryWindowSearchUIState()
    state.text = "clip"
    state.criteria.types.insert(.text)
    state.selectedTokenKind = .type(.text)
    state.isVisible = true
    state.hasHandedOffFocusToCard = true

    let shouldFocusTextInput = state.clearText()

    #expect(state.text.isEmpty)
    #expect(state.criteria.types == [.text])
    #expect(state.selectedTokenKind == nil)
    #expect(state.hasHandedOffFocusToCard == false)
    #expect(shouldFocusTextInput)
}

@Test func searchUIStateClearsTextAndFiltersWithTrigger() {
    var state = HistoryWindowSearchUIState()
    state.text = "clip"
    state.criteria.types.insert(.text)
    state.criteria.sourceAppNames.insert("ClipEase")
    state.criteria.tokenOrder = [.type(.text), .sourceApp("ClipEase")]
    state.selectedTokenKind = .sourceApp("ClipEase")
    state.isVisible = true

    let shouldFocusTextInput = state.clearTextAndFilters(trigger: "search.clearButton")

    #expect(state.text.isEmpty)
    #expect(state.criteria == HistorySearchCriteria())
    #expect(state.selectedTokenKind == nil)
    #expect(state.pendingTrigger == "search.clearButton")
    #expect(shouldFocusTextInput)
}

@Test func searchUIStateTogglesPresentationAndFilterPanel() {
    var state = HistoryWindowSearchUIState()

    state.open(trigger: "search.commandF")
    #expect(state.isVisible)
    #expect(state.pendingTrigger == "search.commandF")

    let openedPanel = state.toggleFilterPanel(openTrigger: "filter.button.open", closeTrigger: "filter.button.close")
    #expect(openedPanel)
    #expect(state.isFilterPanelPresented)
    #expect(state.pendingTrigger == "filter.button.open")

    let closedPanel = state.toggleFilterPanel(openTrigger: "filter.button.open", closeTrigger: "filter.button.close")
    #expect(!closedPanel)
    #expect(!state.isFilterPanelPresented)
    #expect(state.pendingTrigger == "filter.button.close")

    state.close()
    #expect(!state.isVisible)
}

@Test func searchUIStateMaintainsFilterTokenOrder() {
    var state = HistoryWindowSearchUIState()

    state.toggleType(.text)
    state.toggleSourceApp("ClipEase")
    #expect(state.criteria.types == [.text])
    #expect(state.criteria.sourceAppNames == ["ClipEase"])
    #expect(state.criteria.tokenOrder == [.type(.text), .sourceApp("ClipEase")])
    #expect(state.pendingTrigger == "filter.sourceApp.toggle")

    state.toggleType(.text)
    #expect(state.criteria.types.isEmpty)
    #expect(state.criteria.tokenOrder == [.sourceApp("ClipEase")])

    state.removeToken(.sourceApp("ClipEase"))
    #expect(state.criteria.sourceAppNames.isEmpty)
    #expect(state.criteria.tokenOrder.isEmpty)
    #expect(state.selectedTokenKind == nil)
    #expect(state.pendingTrigger == "search.token.remove")
}
