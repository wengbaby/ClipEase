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
    require("LinkTitleFetcher.metadata(for: url)" in fetch_link_metadata,
            "store must use LinkTitleFetcher for title and image metadata")
    require("NSImage.init(data:)" in fetch_link_metadata and ".flatMap(persistence.saveImage)" in fetch_link_metadata,
            "link preview image data must be persisted through the existing image attachment path")
    require("MainActor.run" in fetch_link_metadata and "updateLinkMetadata(" in fetch_link_metadata,
            "background metadata fetch must update the captured item on the main actor")

    update_metadata = body_of_function(store, "updateLinkMetadata")
    require("items[index].url == url" in update_metadata,
            "link metadata update must guard against stale fetches after URL edits")
    require("updatingLinkMetadata(" in update_metadata,
            "link metadata update must preserve unrelated item fields through ClipboardItem helper")
    require("persistence.deleteImage(fileName: oldImageFileName)" in update_metadata,
            "link metadata update must clean up replaced preview images")
    require("scheduleSave()" in update_metadata,
            "link metadata updates must persist after background fetch completes")


def verify_fetcher_and_model() -> None:
    fetcher = FETCHER.read_text(encoding="utf-8")
    model = MODEL.read_text(encoding="utf-8")

    require("enum LinkTitleFetcher" in fetcher and "static func title(for url: URL) async -> String?" in fetcher,
            "LinkTitleFetcher async title API missing")
    require("struct LinkMetadata" in fetcher and "static func metadata(for url: URL) async -> LinkMetadata" in fetcher,
            "LinkTitleFetcher must expose combined title and preview image metadata")
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
            and "AsyncCardImageView(imageFileName: item.imageFileName, mode: .fitWithoutUpscaling(maxSize: 96))" in card_view,
            "link cards must render stored preview images when metadata provides one")
    require("case fitWithoutUpscaling(maxSize: CGFloat)" in card_view
            and "min(max(image.size.width, 1), maxSize)" in card_view
            and "min(max(image.size.height, 1), maxSize)" in card_view,
            "link preview images must not upscale small favicon-style assets")
    require("AsyncCardImageView(imageFileName: item.imageFileName, mode: .fillAvailable)" in card_view,
            "image cards must keep using full available image preview sizing")
    require("linkFallbackIcon" in card_view,
            "link cards must keep the existing icon fallback when metadata has no image")


def main() -> None:
    verify_store()
    verify_fetcher_and_model()
    verify_card_view()
    print("OK link metadata background fetch checks passed")


if __name__ == "__main__":
    main()
