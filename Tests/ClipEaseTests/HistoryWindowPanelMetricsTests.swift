import Testing
@testable import ClipEase

@Test func historyWindowPanelMetricsMatchRenderedContentHeight() {
    #expect(HistoryWindowPanelMetrics.height == 360)
    #expect(HistoryWindowPanelMetrics.animationDistance == HistoryWindowPanelMetrics.height)
    #expect(HistoryWindowPanelMetrics.cardHeight == 270)
    #expect(HistoryWindowPanelMetrics.railFrameHeight == 270)
    #expect(
        HistoryWindowPanelMetrics.topPadding +
            HistoryWindowPanelMetrics.toolbarHeight +
            HistoryWindowPanelMetrics.toolbarRailSpacing +
            HistoryWindowPanelMetrics.railFrameHeight +
            HistoryWindowPanelMetrics.selectedCardTopContentInset +
            HistoryWindowPanelMetrics.railBottomPadding ==
            HistoryWindowPanelMetrics.height
    )
}
