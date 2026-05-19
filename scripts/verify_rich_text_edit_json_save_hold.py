#!/usr/bin/env python3
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
STORE = ROOT / "Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift"


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    sys.exit(1)


def main() -> None:
    source = STORE.read_text(encoding="utf-8")
    match = re.search(
        r"func updateRichTextContent\(.*?\n    func imageFileURL",
        source,
        flags=re.S,
    )
    if not match:
        fail("Could not locate updateRichTextContent body")

    body = match.group(0)
    catch_match = re.search(r"\} catch \{(.*?)throw error", body, flags=re.S)
    if not catch_match:
        fail("Could not locate saveImmediatelyOrThrow catch rollback")

    catch_body = catch_match.group(1)
    if "items[index] = item" not in catch_body:
        fail("Rollback path must restore items[index]")
    if "rebuildRecentHashes()" not in catch_body:
        fail("Rollback path must rebuild recentHashes")
    if "deleteRichText" in catch_body or "storedRichText.fileName" in catch_body:
        fail("Rollback path must not delete the newly stored RTF")

    success_delete = "persistence.deleteRichText(fileName: richTextFileName)"
    if success_delete not in body:
        fail("Success path must still delete the old RTF")

    print("OK: rich text edit rollback keeps new RTF; success path deletes old RTF")


if __name__ == "__main__":
    main()
