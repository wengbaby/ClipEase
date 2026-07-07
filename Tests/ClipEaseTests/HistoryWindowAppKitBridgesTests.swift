import Testing
@testable import ClipEase

@Test func appKitBridgeTypesAreAvailableInsideHistoryWindowModule() {
    let hostReaderType = HistoryWindowHostWindowReader.self
    let searchOutsideObserverType = SearchOutsideWindowMouseDownObserver.self
    let horizontalRedirectorType = HorizontalScrollWheelRedirector.self
    let cardRailScope = HorizontalScrollWheelRedirector.Scope.cardRail

    #expect(String(describing: hostReaderType).contains("HistoryWindowHostWindowReader"))
    #expect(String(describing: searchOutsideObserverType).contains("SearchOutsideWindowMouseDownObserver"))
    #expect(String(describing: horizontalRedirectorType).contains("HorizontalScrollWheelRedirector"))
    #expect(String(describing: cardRailScope).contains("cardRail"))
}
