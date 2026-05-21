#!/usr/bin/env python3
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
STORE = ROOT / "Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift"
FETCHER = ROOT / "Sources/ClipEase/Core/Utilities/LinkTitleFetcher.swift"
MODEL = ROOT / "Sources/ClipEase/Core/Models/ClipboardItem.swift"


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    sys.exit(1)


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def body_of_function(source: str, name: str) -> str:
    match = re.search(rf"\bfunc\s+{re.escape(name)}\b[^\{{]*\{{", source)
    if not match:
        fail(f"missing function {name}")

    depth = 1
    index = match.end()
    while index < len(source) and depth > 0:
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
        index += 1
    return source[match.end():index - 1]


def verify_store() -> None:
    store = STORE.read_text(encoding="utf-8")

    add_text = body_of_function(store, "addText")
    require(".link(" in add_text, "addText must still create link items from URLs")
    require("let upsertedItem = upsertClipboardItem(item)" in add_text,
            "addText must insert captured items through the unified upsert path")
    require("fetchLinkTitle(for: upsertedItem.id, url: url)" in add_text,
            "captured link items must start background metadata fetch from addText")
    require('item.linkTitle == "/"' not in add_text,
            "background title fetch must not be limited to root-path fallback titles")

    fetch_link_title = body_of_function(store, "fetchLinkTitle")
    require("fetchLinkMetadata(for: id, url: url)" in fetch_link_title,
            "compatibility title fetch path must delegate to metadata fetch")

    fetch_link_metadata = body_of_function(store, "fetchLinkMetadata")
    require("Task.detached(priority: .utility)" in fetch_link_metadata,
            "link metadata fetch must run off the main capture path")
    require("linkMetadataTaskByItemID[id]?.cancel()" in fetch_link_metadata
            and "linkMetadataTaskByItemID[id] = Task.detached(priority: .utility)" in fetch_link_metadata,
            "new link metadata fetches must cancel and replace older fetches for the same item")
    require("let generation = nextLinkMetadataGeneration(for: id)" in fetch_link_metadata
            and "finishLinkMetadataTask(for: id, generation: generation)" in fetch_link_metadata,
            "link metadata fetches must use generation cleanup so stale tasks cannot clear newer state")
    require("try Task.checkCancellation()" in fetch_link_metadata
            and "guard !Task.isCancelled else" in fetch_link_metadata,
            "link metadata fetch must honor cancellation before and between expensive phases")
    require("LinkMetadataFetchLimiter.shared.waitForTurn()" in fetch_link_metadata
            and "LinkMetadataFetchLimiter.shared.finishTurn()" in fetch_link_metadata,
            "link metadata fetches must use a bounded background concurrency limiter")
    require("var didEnterLimiter = false" in fetch_link_metadata
            and "if didEnterLimiter" in fetch_link_metadata,
            "cancelled link metadata tasks must only release limiter slots they actually acquired")
    require("await Task.yield()" in fetch_link_metadata,
            "link metadata fetch must yield between title and image phases")
    require("LinkTitleFetcher.pageMetadata(for: url)" in fetch_link_metadata,
            "store must fetch page metadata once before image download")
    title_update_index = fetch_link_metadata.find("storedImage: nil")
    image_fetch_index = fetch_link_metadata.find("LinkTitleFetcher.previewImageData(from: pageMetadata, baseURL: url)")
    require(title_update_index != -1 and image_fetch_index != -1 and title_update_index < image_fetch_index,
            "store must update fetched link titles before waiting on preview image downloads")
    require("LinkTitleFetcher.previewImageData(from: pageMetadata, baseURL: url)" in fetch_link_metadata,
            "store must reuse fetched page HTML for preview image lookup")
    require("LinkTitleFetcher.metadata(for: url)" not in fetch_link_metadata,
            "store must not refetch page metadata while downloading preview images")
    require("NSImage.init(data:)" in fetch_link_metadata and ".flatMap(persistence.saveImage)" in fetch_link_metadata,
            "link preview image data must be persisted through the existing image attachment path")
    require("await self?.updateLinkMetadata(" in fetch_link_metadata
            and "await self?.finishLinkMetadataTask(for: id, generation: generation)" in fetch_link_metadata,
            "background metadata fetch must update and clean up through main-actor store methods")

    update_metadata = body_of_function(store, "updateLinkMetadata")
    require("items[index].url == url" in update_metadata,
            "link metadata update must guard against stale fetches after URL edits")
    require("updatingLinkMetadata(" in update_metadata,
            "link metadata update must preserve unrelated item fields through ClipboardItem helper")
    require("persistence.deleteImage(fileName: oldImageFileName)" in update_metadata,
            "link metadata update must clean up replaced preview images")
    require("scheduleSave()" in update_metadata,
            "link metadata updates must persist after background fetch completes")

    require("private actor LinkMetadataFetchLimiter" in store
            and "private let limit = 3" in store
            and "CheckedContinuation<Void, Never>" in store,
            "link metadata concurrency limiter must bound simultaneous background fetches")
    require("private var linkMetadataTaskByItemID: [ClipboardItem.ID: Task<Void, Never>] = [:]" in store
            and "private var linkMetadataGenerationByItemID: [ClipboardItem.ID: Int] = [:]" in store,
            "store must retain cancellable link metadata tasks and generations")
    require("private func cancelLinkMetadataTasks(for removedItems: [ClipboardItem])" in store
            and "private func cancelAllLinkMetadataTasks()" in store,
            "store must expose internal link metadata cancellation helpers")

    delete_item = body_of_function(store, "deleteItem")
    clear_all = body_of_function(store, "clearAllItems")
    delete_group = body_of_function(store, "deleteGroup")
    delete_groups = body_of_function(store, "deleteGroups")
    prune_expired = body_of_function(store, "pruneExpiredItems")
    upsert = body_of_function(store, "upsertClipboardItem")
    require("cancelLinkMetadataTasks(for: deletedItems)" in delete_item,
            "deleting one item must cancel its link metadata task")
    require("cancelAllLinkMetadataTasks()" in clear_all,
            "clearing history must cancel every link metadata task")
    require("cancelLinkMetadataTasks(for: removedItems)" in delete_group
            and "cancelLinkMetadataTasks(for: removedItems)" in delete_groups
            and "cancelLinkMetadataTasks(for: removedItems)" in prune_expired,
            "bulk removals and retention pruning must cancel removed link metadata tasks")
    require("cancelLinkMetadataTasks(for: duplicateIDs)" in upsert,
            "deduplicating items must cancel metadata tasks for replaced duplicates")


def verify_fetcher_and_model() -> None:
    fetcher = FETCHER.read_text(encoding="utf-8")
    model = MODEL.read_text(encoding="utf-8")

    require("enum LinkTitleFetcher" in fetcher and "static func title(for url: URL) async -> String?" in fetcher,
            "LinkTitleFetcher async title API missing")
    require("struct LinkMetadata" in fetcher and "static func metadata(for url: URL) async -> LinkMetadata" in fetcher,
            "LinkTitleFetcher must expose combined title and preview image metadata")
    require("struct LinkPageMetadata" in fetcher
            and "static func pageMetadata(for url: URL) async -> LinkPageMetadata?" in fetcher
            and "static func previewImageData(from pageMetadata: LinkPageMetadata, baseURL: URL) async -> Data?" in fetcher,
            "LinkTitleFetcher must support fast title-first metadata updates")
    require("URLSession.shared.data(for: request)" in fetcher,
            "LinkTitleFetcher must fetch metadata through URLSession")
    require("<title" in fetcher and "decodeHTMLEntities" in fetcher,
            "LinkTitleFetcher must extract and decode HTML titles")
    require("og:image" in fetcher and "twitter:image" in fetcher,
            "LinkTitleFetcher must look for standard social preview image metadata")
    require("fluid-icon" in fetcher and "apple-touch-icon" in fetcher,
            "LinkTitleFetcher must fall back to site icon metadata for GitHub-style previews")
    require("fetchPreviewImage" in fetcher and "data.count <= 5_000_000" in fetcher,
            "LinkTitleFetcher must download bounded preview image data")
    require("var linkTitle: String?" in model,
            "ClipboardItem must keep using the existing linkTitle field without schema changes")
    require("func updatingLinkMetadata(" in model,
            "ClipboardItem must provide a surgical helper for link metadata updates")


def verify_card_view() -> None:
    card_view = (ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryCardView.swift").read_text(encoding="utf-8")
    require("if item.imageFileName != nil" in card_view
            and "mode: .fitLinkPreview(minSize: 52, maxSize: 96)" in card_view,
            "link cards must render stored preview images when metadata provides one")
    require("case fitLinkPreview(minSize: CGFloat, maxSize: CGFloat)" in card_view
            and "min(max(image.size.width, minSize), maxSize)" in card_view
            and "min(max(image.size.height, minSize), maxSize)" in card_view,
            "link preview images must stay between the fallback icon size and the large preview cap")
    require("AsyncCardImageView(imageFileName: item.imageFileName, mode: .fillAvailable)" in card_view,
            "image cards must keep using full available image preview sizing")
    require("linkFallbackIcon" in card_view,
            "link cards must keep the existing icon fallback when metadata has no image")


def verify_link_preview_webview() -> None:
    webview = (ROOT / "Sources/ClipEase/Features/HistoryWindow/LinkPreviewWebView.swift").read_text(encoding="utf-8")
    popover = (ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryPreviewPopoverView.swift").read_text(encoding="utf-8")

    require("WKNavigationDelegate" in webview and "webView.navigationDelegate = context.coordinator" in webview,
            "link preview web view must observe load success and failure")
    require("didFinish navigation" in webview
            and "didFail navigation" in webview
            and "didFailProvisionalNavigation" in webview,
            "link preview web view must report both committed and provisional failures")
    require("isLinkPreviewLoading" in popover
            and "linkPreviewError" in popover
            and "linkPreviewOverlay" in popover,
            "link preview popover must show loading and failure states instead of blank content")
    require("无法加载链接预览" in popover and "正在加载链接预览" in popover,
            "link preview overlay must provide clear user-visible state text")


def main() -> None:
    verify_store()
    verify_fetcher_and_model()
    verify_card_view()
    verify_link_preview_webview()
    print("OK link metadata background fetch checks passed")


if __name__ == "__main__":
    main()
