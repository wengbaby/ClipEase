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
    require("items.insert(item, at: 0)" in add_text, "addText must insert captured items immediately")
    require("fetchLinkTitle(for: item.id, url: url)" in add_text,
            "captured link items must start background title fetch from addText")
    require('item.linkTitle == "/"' not in add_text,
            "background title fetch must not be limited to root-path fallback titles")

    fetch_link_title = body_of_function(store, "fetchLinkTitle")
    require("Task.detached(priority: .utility)" in fetch_link_title,
            "link title fetch must run off the main capture path")
    require("LinkTitleFetcher.title(for: url)" in fetch_link_title,
            "store must use LinkTitleFetcher for title metadata")
    require("MainActor.run" in fetch_link_title and "updateLinkTitle(title, for: id, url: url)" in fetch_link_title,
            "background title fetch must update the captured item on the main actor")

    update_title = body_of_function(store, "updateLinkTitle")
    require("items[index].url == url" in update_title,
            "link title update must guard against stale fetches after URL edits")
    require("scheduleSave()" in update_title,
            "link title updates must persist after background fetch completes")


def verify_fetcher_and_model() -> None:
    fetcher = FETCHER.read_text(encoding="utf-8")
    model = MODEL.read_text(encoding="utf-8")

    require("enum LinkTitleFetcher" in fetcher and "static func title(for url: URL) async -> String?" in fetcher,
            "LinkTitleFetcher async title API missing")
    require("URLSession.shared.data(for: request)" in fetcher,
            "LinkTitleFetcher must fetch metadata through URLSession")
    require("<title" in fetcher and "decodeHTMLEntities" in fetcher,
            "LinkTitleFetcher must extract and decode HTML titles")
    require("var linkTitle: String?" in model,
            "ClipboardItem must keep using the existing linkTitle field without schema changes")


def main() -> None:
    verify_store()
    verify_fetcher_and_model()
    print("OK link title background fetch checks passed")


if __name__ == "__main__":
    main()
