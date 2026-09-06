import SwiftUI
import AppKit

extension HistoryWindowView {
    func copyItem(_ id: ClipboardItem.ID?) {
        guard let item = actionableItem(with: id) else {
            return
        }

        switch pasteExecutor.copyToPasteboard(item) {
        case .copied:
            store.markUsed(item.id)
            ClipEaseSoundPlayer.shared.playCopyFeedback()
            showStatus(copyStatus(for: item))
        case .copiedFallbackText:
            store.markUsed(item.id)
            ClipEaseSoundPlayer.shared.playCopyFeedback()
            showStatus(copyFallbackTextStatus(for: item))
        case .failed(let reason):
            showStatus(reason)
        }
    }

    func copyPlainTextItem(_ id: ClipboardItem.ID?) {
        guard let item = actionableItem(with: id) else {
            return
        }

        switch pasteExecutor.copyPlainTextToPasteboard(item) {
        case .copied, .copiedFallbackText:
            store.markUsed(item.id)
            ClipEaseSoundPlayer.shared.playCopyFeedback()
            showStatus(L("已复制纯文本"))
        case .failed(let reason):
            showStatus(reason)
        }
    }

    func pastePlainTextItem(_ id: ClipboardItem.ID?) {
        guard let item = actionableItem(with: id) else {
            return
        }
        accessibilityPermissionState.refresh()
        preparePastedItemFocus(item.id)
        switch pasteExecutor.pastePlainTextToFrontmostApp(item) {
        case .copiedOnly, .copiedFallbackTextOnly:
            store.markUsed(item.id)
            showStatus(L("已复制纯文本，需授权后自动粘贴"))
            closeAfterPasteIfNeeded()
        case .pasted, .pastedFallbackText:
            store.markUsed(item.id)
            scheduleProgrammaticJump(to: item.id)
            showStatus(L("已粘贴纯文本到当前 App"))
        case .failed(let reason):
            focusState.pendingPastedItemFocusOnNextShow = nil
            showStatus(reason)
        }
    }

    func copyMarkdownLink(_ id: ClipboardItem.ID?) {
        guard let item = displayedSourceItem(with: id),
              item.type == .link else {
            return
        }

        let title = (item.linkTitle?.isEmpty == false ? item.linkTitle : nil)
            ?? item.url?.host(percentEncoded: false)
            ?? item.text
        let markdown = "[\(title)](\(item.text))"
        guard case .copied = pasteExecutor.copyTextToPasteboard(markdown) else {
            showStatus(L("无法写入剪贴板"))
            return
        }
        ClipEaseSoundPlayer.shared.playCopyFeedback()
        showStatus(L("已复制 Markdown 链接"))
        closeAfterContextMenuCommand()
    }

    func copyLinkURL(_ id: ClipboardItem.ID?) {
        guard let item = displayedSourceItem(with: id),
              item.type == .link else {
            return
        }

        guard case .copied = pasteExecutor.copyTextToPasteboard(item.text) else {
            showStatus(L("无法写入剪贴板"))
            return
        }
        ClipEaseSoundPlayer.shared.playCopyFeedback()
        showStatus(L("已复制链接地址"))
        closeAfterContextMenuCommand()
    }

    func openLink(_ id: ClipboardItem.ID?) {
        guard let item = displayedSourceItem(with: id),
              item.type == .link,
              let url = item.url else {
            showStatus(L("无法打开链接"))
            return
        }

        NSWorkspace.shared.open(url)
        showStatus(L("已打开链接"))
        closeAfterContextMenuCommand()
    }

    func copyColorHex(_ id: ClipboardItem.ID?) {
        guard let item = displayedSourceItem(with: id),
              item.type == .color else {
            return
        }

        guard case .copied = pasteExecutor.copyTextToPasteboard(item.text) else {
            showStatus(L("无法写入剪贴板"))
            return
        }
        ClipEaseSoundPlayer.shared.playCopyFeedback()
        showStatus(L("已复制 HEX"))
        closeAfterContextMenuCommand()
    }

    func copyColorRGB(_ id: ClipboardItem.ID?) {
        guard let item = displayedSourceItem(with: id),
              item.type == .color,
              let rgb = rgbString(from: item.text) else {
            showStatus(L("无法转换 RGB"))
            return
        }

        guard case .copied = pasteExecutor.copyTextToPasteboard(rgb) else {
            showStatus(L("无法写入剪贴板"))
            return
        }
        ClipEaseSoundPlayer.shared.playCopyFeedback()
        showStatus(L("已复制 RGB"))
        closeAfterContextMenuCommand()
    }

    func pasteItem(_ id: ClipboardItem.ID?) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        guard containsFilteredItem(id),
              let item = actionableItem(with: id) else {
            if searchUIState.isVisible {
                showStatus(L("没有可粘贴的搜索结果"))
            }
            return
        }

        accessibilityPermissionState.refresh()
        preparePastedItemFocus(item.id)
        switch pasteExecutor.pasteToFrontmostApp(item) {
        case .copiedOnly:
            store.markUsed(item.id)
            showStatus(copiedOnlyStatus(for: item))
            closeAfterPasteIfNeeded()
        case .copiedFallbackTextOnly:
            store.markUsed(item.id)
            showStatus(copiedOnlyFallbackTextStatus(for: item))
            closeAfterPasteIfNeeded()
        case .pasted:
            store.markUsed(item.id)
            scheduleProgrammaticJump(to: item.id)
            showStatus(pastedStatus(for: item))
        case .pastedFallbackText:
            store.markUsed(item.id)
            scheduleProgrammaticJump(to: item.id)
            showStatus(pastedFallbackTextStatus(for: item))
        case .failed(let reason):
            focusState.pendingPastedItemFocusOnNextShow = nil
            showStatus(reason)
        }
        PerformanceDiagnosticsService.shared.record(
            "paste.item",
            category: "interaction",
            durationMS: (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000,
            itemCount: filteredItems.count,
            metadata: ["itemType": "\(item.type)"]
        )
    }

    func showPreview(_ id: ClipboardItem.ID?) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        guard let item = displayedSourceItem(with: id) else {
            return
        }

        guard let cardFrame = cardViewportFrame(for: item.id) else {
            previewCoordinator.markNeedsFollow(item.id)
            keepKeyboardFocusedItemRendered(item.id)
            scrollToItemWhenRendered(item.id, animated: false)
            followPreviewForCurrentScroll()
            return
        }

        onPreview(item, cardFrame)
        PerformanceDiagnosticsService.shared.record(
            "preview.show",
            category: "preview",
            durationMS: (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000,
            itemCount: renderedItems.count,
            metadata: ["itemType": "\(item.type)"]
        )
    }

    func isEditable(_ item: HistoryPreviewItem) -> Bool {
        guard let sourceItem = displayedSourceItem(with: item.id) else {
            return false
        }

        return isEditable(sourceItem)
    }

    func isEditable(_ item: ClipboardItem) -> Bool {
        switch item.type {
        case .text:
            true
        case .link, .color:
            true
        case .image:
            false
        case .file:
            false
        }
    }

    func handleEditShortcut() {
        guard canEditSelectedItemFromShortcut else {
            return
        }

        beginEditItem(selectedItemID)
    }

    func beginEditItem(_ id: ClipboardItem.ID?) {
        guard let item = actionableItem(with: id),
              isEditable(item) else {
            showStatus(L("此内容暂不支持编辑"))
            return
        }

        closePreview()
        onClose()
        appMenuController.editItem(item) { updatedItem in
            selectedItemID = updatedItem.id
            if updatedItem.type == .link {
                _ = pasteExecutor.copyTextToPasteboard(updatedItem.text)
                ClipEaseSoundPlayer.shared.playCopyFeedback()
                showStatus(L("已保存并复制新链接"))
            } else {
                showStatus(L("已保存"))
            }
        }
    }

    func deleteItem(_ id: ClipboardItem.ID?) {
        guard !inputState.isAnyTextInputActiveSnapshot,
              canPerformDeleteCommand,
              let id,
              let item = displayedSourceItem(with: id) else {
            return
        }

        let nextID = nextSelectionID(afterDeleting: id)
        if store.item(with: id) != nil {
            suppressNextListMembershipReset = true
        }
        store.deletePersistedSearchItem(item)
        removeFilteredPreviewItem(with: id)
        selectedItemID = nextID
        if previewState.itemID == id {
            closePreview()
        }
        showStatus(L("已删除"))
    }

    func presentMoveToGroupPicker(for item: HistoryPreviewItem) {
        groupUIState.presentMoveToGroupPicker(for: item)
    }

    func removeItemFromGroup(_ id: ClipboardItem.ID?) {
        guard actionableItem(with: id) != nil else {
            return
        }
        let adjacentSelectionID: ClipboardItem.ID?
        if case .group = groupUIState.selectedGroup,
           let id,
           selectedItemID == id {
            adjacentSelectionID = HistoryRemovedItemSelectionPolicy.selectedID(
                removingID: id,
                orderedIDs: filteredItems.map(\.id)
            )
        } else {
            adjacentSelectionID = nil
        }

        store.removeItemFromGroup(id)
        applyItemGroupMutationFromStore(id)
        if selectedItemID == id,
           case .group = groupUIState.selectedGroup {
            selectedItemID = adjacentSelectionID
            if let adjacentSelectionID {
                keepKeyboardFocusedItemRendered(adjacentSelectionID)
            } else {
                closePreview()
            }
        }
        scheduleSearchUpdate(immediate: true, debounceNanoseconds: 0)
        showStatus(L("已移出分组"))
    }

    func togglePinned(_ id: ClipboardItem.ID?) {
        guard let item = actionableItem(with: id) else {
            return
        }

        store.togglePinned(for: id)
        showStatus(item.isPinned ? L("已取消置顶") : L("已置顶"))
    }

    func sourceAppIgnoreMenuTitle(for item: ClipboardItem) -> String {
        let prefix = appMenuController.isSourceAppIgnored(for: item) ? L("取消忽略") : L("忽略")
        return "\(prefix) \(item.sourceAppName)"
    }

    func toggleSourceAppIgnored(_ id: ClipboardItem.ID?) {
        guard let item = displayedSourceItem(with: id),
              item.sourceBundleID != nil else {
            showStatus(L("无法识别来源 App"))
            return
        }

        guard !item.isFromClipEase else {
            showStatus(L("轻贴自身内容不能忽略"))
            return
        }

        if appMenuController.isSourceAppIgnored(for: item) {
            appMenuController.unignoreSourceApp(for: item)
            showStatus(L("已取消忽略 \(item.sourceAppName)"))
            return
        }

        appMenuController.ignoreSourceApp(for: item)
        showStatus(L("已忽略 \(item.sourceAppName)"))
    }

    func copySourceAppName(_ id: ClipboardItem.ID?) {
        guard let item = displayedSourceItem(with: id) else {
            return
        }

        guard case .copied = pasteExecutor.copyTextToPasteboard(item.sourceAppName) else {
            showStatus(L("无法写入剪贴板"))
            return
        }
        showStatus(L("已复制来源名称"))
        closeAfterContextMenuCommand()
    }

    func copySourceBundleID(_ id: ClipboardItem.ID?) {
        guard let item = displayedSourceItem(with: id),
              let bundleID = item.sourceBundleID else {
            showStatus(L("无来源 Bundle ID"))
            return
        }

        guard case .copied = pasteExecutor.copyTextToPasteboard(bundleID) else {
            showStatus(L("无法写入剪贴板"))
            return
        }
        showStatus(L("已复制 Bundle ID"))
        closeAfterContextMenuCommand()
    }

    func revealImageInFinder(_ id: ClipboardItem.ID?) {
        guard let item = displayedSourceItem(with: id),
              let imageURL = store.imageFileURL(for: item) else {
            showStatus(L("未找到图片文件"))
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([imageURL])
        showStatus(L("已在 Finder 中显示"))
        closeAfterContextMenuCommand()
    }

    func openImage(_ id: ClipboardItem.ID?) {
        guard let item = displayedSourceItem(with: id),
              let imageURL = store.imageFileURL(for: item) else {
            showStatus(L("未找到图片文件"))
            return
        }

        NSWorkspace.shared.open(imageURL)
        showStatus(L("已打开图片"))
        closeAfterContextMenuCommand()
    }

    func copyImage(_ id: ClipboardItem.ID?) {
        guard let item = displayedSourceItem(with: id),
              let imageURL = store.imageFileURL(for: item),
              let image = NSImage(contentsOf: imageURL) else {
            showStatus(L("未找到图片文件"))
            return
        }

        guard case .copied = pasteExecutor.copyImageToPasteboard(
            image,
            skipText: item.preview.isEmpty ? imageURL.lastPathComponent : item.preview
        ) else {
            showStatus(L("无法写入图片到剪贴板"))
            return
        }
        ClipEaseSoundPlayer.shared.playCopyFeedback()
        showStatus(L("已复制图像"))
        closeAfterContextMenuCommand()
    }

    func copyImagePath(_ id: ClipboardItem.ID?) {
        guard let item = displayedSourceItem(with: id),
              let imageURL = store.imageFileURL(for: item) else {
            showStatus(L("未找到图片文件"))
            return
        }

        let path = imageURL.path
        guard case .copied = pasteExecutor.copyTextToPasteboard(path) else {
            showStatus(L("无法写入剪贴板"))
            return
        }
        ClipEaseSoundPlayer.shared.playCopyFeedback()
        showStatus(L("已复制图片路径"))
        closeAfterContextMenuCommand()
    }

    func copyFilePaths(_ id: ClipboardItem.ID?) {
        guard let item = displayedSourceItem(with: id),
              item.type == .file else {
            showStatus(L("未找到文件"))
            return
        }

        let paths = item.fileReferences
            .map(\.path)
            .filter { !$0.isEmpty }

        guard !paths.isEmpty else {
            showStatus(L("未找到文件"))
            return
        }

        let pathsText = paths.joined(separator: "\n")
        guard case .copied = pasteExecutor.copyTextToPasteboard(pathsText) else {
            showStatus(L("无法写入剪贴板"))
            return
        }
        ClipEaseSoundPlayer.shared.playCopyFeedback()
        showStatus(paths.count > 1 ? L("已复制 \(paths.count) 个文件路径") : L("已复制文件路径"))
        closeAfterContextMenuCommand()
    }

    func copyFile(_ id: ClipboardItem.ID?) {
        guard let item = displayedSourceItem(with: id),
              item.type == .file else {
            showStatus(L("未找到文件"))
            return
        }

        let urls = existingFileURLs(for: item)
        guard let firstURL = urls.first else {
            showStatus(L("未找到文件"))
            return
        }

        guard case .copied = pasteExecutor.copyFileURLToPasteboard(firstURL) else {
            showStatus(L("无法写入文件引用到剪贴板"))
            return
        }
        ClipEaseSoundPlayer.shared.playCopyFeedback()
        showStatus(L("已复制文件"))
        closeAfterContextMenuCommand()
    }

    func openFile(_ id: ClipboardItem.ID?) {
        guard let item = displayedSourceItem(with: id),
              item.type == .file else {
            showStatus(L("未找到文件"))
            return
        }

        let urls = existingFileURLs(for: item)
        guard let firstURL = urls.first else {
            showStatus(L("未找到文件"))
            return
        }

        NSWorkspace.shared.open(firstURL)
        showStatus(L("已打开文件"))
        closeAfterContextMenuCommand()
    }

    func revealFilesInFinder(_ id: ClipboardItem.ID?) {
        guard let item = displayedSourceItem(with: id),
              item.type == .file else {
            showStatus(L("未找到文件"))
            return
        }

        let urls = existingFileURLs(for: item)
        guard !urls.isEmpty else {
            showStatus(L("未找到文件"))
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting(urls)
        showStatus(L("已在 Finder 中显示"))
        closeAfterContextMenuCommand()
    }

    func selectCardForPrimaryClick(_ item: HistoryPreviewItem) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        blurSearchFieldForCardInteraction()

        if previewState.isVisible {
            closePreview()
        }

        if selectedItemID != item.id {
            selectedItemID = item.id
        }
        markUserCardNavigation()

        if !revealPartiallyVisibleCardIfNeeded(item.id) {
            scrollToItemWhenRendered(item.id, animated: true)
        }
        PerformanceDiagnosticsService.shared.record(
            "card.click",
            category: "interaction",
            durationMS: (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000,
            itemCount: renderedItems.count,
            metadata: ["itemType": "\(item.type)"]
        )
    }

    func selectCardForContextMenu(_ item: HistoryPreviewItem) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        blurSearchFieldForCardInteraction()

        if previewState.isVisible {
            closePreview()
        }

        if selectedItemID != item.id {
            selectedItemID = item.id
        }
        markUserCardNavigation()

        if !revealPartiallyVisibleCardIfNeeded(item.id) {
            scrollToItemWhenRendered(item.id, animated: true)
        }
        PerformanceDiagnosticsService.shared.record(
            "card.contextMenuSelect",
            category: "interaction",
            durationMS: (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000,
            itemCount: renderedItems.count,
            metadata: ["itemType": "\(item.type)"]
        )
    }

    func blurSearchFieldForCardInteraction() {
        guard isSearchFocused || inputState.isTextInputFocusedSnapshot else {
            return
        }

        isSearchFocused = false
        inputState.setTextInputFocused(false)
        hostWindow?.makeFirstResponder(nil)
    }
}
