import AppKit
@preconcurrency import Quartz

@MainActor
final class HistorySystemQuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private var items: [HistorySystemQuickLookItem] = []
    private var selectedIndex = 0

    var isVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared()?.isVisible == true
    }

    func contains(screenPoint: CGPoint) -> Bool {
        guard QLPreviewPanel.sharedPreviewPanelExists(),
              let panel = QLPreviewPanel.shared(),
              panel.isVisible else {
            return false
        }

        return panel.frame.contains(screenPoint)
    }

    func show(urls: [URL], selectedURL: URL? = nil) -> Bool {
        items = urls
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map(HistorySystemQuickLookItem.init)
        guard !items.isEmpty,
              let panel = QLPreviewPanel.shared() else {
            close()
            return false
        }

        if let selectedURL,
           let index = items.firstIndex(where: { $0.previewItemURL?.standardizedFileURL == selectedURL.standardizedFileURL }) {
            selectedIndex = index
        } else {
            selectedIndex = 0
        }

        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = selectedIndex
        panel.makeKeyAndOrderFront(nil)
        return true
    }

    func close() {
        guard QLPreviewPanel.sharedPreviewPanelExists(),
              let panel = QLPreviewPanel.shared() else {
            items = []
            selectedIndex = 0
            return
        }

        panel.orderOut(nil)
        panel.dataSource = nil
        panel.delegate = nil
        items = []
        selectedIndex = 0
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated {
            items.count
        }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated {
            guard items.indices.contains(index) else {
                return nil
            }

            return items[index]
        }
    }
}

private final class HistorySystemQuickLookItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?

    init(url: URL) {
        previewItemURL = url
    }
}
