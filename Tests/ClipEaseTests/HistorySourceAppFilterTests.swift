import Foundation
import Testing
@testable import ClipEase

@Test func sourceAppFilterSnapshotSkipsEmptyNamesAndKeepsStableFirstSeenOrder() {
    let items = [
        sourceItem(name: "Safari", iconFileName: "safari.icns"),
        sourceItem(name: "   ", iconFileName: "blank.icns"),
        sourceItem(name: "Xcode", iconFileName: "xcode.icns"),
        sourceItem(name: "Safari", iconFileName: "safari-later.icns"),
        sourceItem(name: "Notes", iconFileName: nil)
    ]

    let snapshot = HistorySourceAppFilter.snapshot(from: items)

    #expect(snapshot.options.map(\.name) == ["Safari", "Xcode", "Notes"])
    #expect(snapshot.options.map(\.iconFileName) == ["safari.icns", "xcode.icns", nil])
}

@Test func sourceAppFilterSnapshotKeepsFirstAvailableIconFileNameLookup() {
    let items = [
        sourceItem(name: "Safari", iconFileName: nil),
        sourceItem(name: "Safari", iconFileName: "safari.icns"),
        sourceItem(name: "Safari", iconFileName: "safari-later.icns"),
        sourceItem(name: "Xcode", iconFileName: "xcode.icns")
    ]

    let snapshot = HistorySourceAppFilter.snapshot(from: items)

    #expect(snapshot.iconFileNameByName["Safari"] == "safari.icns")
    #expect(snapshot.iconFileNameByName["Xcode"] == "xcode.icns")
}

private func sourceItem(name: String, iconFileName: String?) -> ClipboardItem {
    ClipboardItem(
        id: UUID(),
        type: .text,
        text: "sample",
        url: nil,
        linkTitle: nil,
        linkSubtitle: nil,
        imageFileName: nil,
        imageWidth: nil,
        imageHeight: nil,
        imageHash: nil,
        richTextFileName: nil,
        fileReferences: [],
        createdAt: Date(timeIntervalSince1970: 1_000),
        sourceAppName: name,
        sourceBundleID: nil,
        iconName: "app.fill",
        iconFileName: iconFileName,
        headerColorHex: "#2E8CFF",
        isPinned: false,
        pinnedAt: nil,
        groupID: nil,
        groupedAt: nil
    )
}
