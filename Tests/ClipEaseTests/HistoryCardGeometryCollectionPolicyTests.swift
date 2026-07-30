import CoreGraphics
import Foundation
import Testing
@testable import ClipEase

@Test func cardGeometryCollectionTracksOnlyActiveAnchors() {
    let selectedID = UUID()
    let previewedID = UUID()
    let pendingScrollID = UUID()
    let pendingJumpID = UUID()

    #expect(
        HistoryCardGeometryCollectionPolicy.trackedIDs(
            previewedID: nil,
            selectedID: nil,
            pendingScrollID: nil,
            pendingProgrammaticJumpID: nil
        ).isEmpty
    )

    #expect(
        HistoryCardGeometryCollectionPolicy.trackedIDs(
            previewedID: previewedID,
            selectedID: selectedID,
            pendingScrollID: pendingScrollID,
            pendingProgrammaticJumpID: pendingJumpID
        ) == [previewedID, selectedID, pendingScrollID, pendingJumpID]
    )
}

@Test func cardGeometryCollectionIgnoresChangesBelowOnePhysicalPixel() {
    let id = UUID()
    let current = [id: CGRect(x: 10, y: 20, width: 250, height: 270)]

    #expect(
        !HistoryCardGeometryCollectionPolicy.shouldPublish(
            current: current,
            incoming: [id: CGRect(x: 10.49, y: 20.49, width: 250.49, height: 270.49)],
            backingScaleFactor: 2
        )
    )
    #expect(
        HistoryCardGeometryCollectionPolicy.shouldPublish(
            current: current,
            incoming: [id: CGRect(x: 10.5, y: 20, width: 250, height: 270)],
            backingScaleFactor: 2
        )
    )
}

@Test func cardGeometryCollectionPublishesMembershipChanges() {
    let first = UUID()
    let second = UUID()
    let frame = CGRect(x: 10, y: 20, width: 250, height: 270)

    #expect(
        HistoryCardGeometryCollectionPolicy.shouldPublish(
            current: [first: frame],
            incoming: [second: frame],
            backingScaleFactor: 2
        )
    )
}
