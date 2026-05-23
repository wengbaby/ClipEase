#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HISTORY_VIEW = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"
HISTORY_CONTROLLER = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift"
STORE = ROOT / "Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift"


def extract_function(source: str, signature: str) -> str:
    start = source.find(signature)
    if start == -1:
        raise AssertionError(f"Missing function signature: {signature}")

    brace = source.find("{", start)
    if brace == -1:
        raise AssertionError(f"Missing function body: {signature}")

    depth = 0
    for index in range(brace, len(source)):
        character = source[index]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return source[start:index + 1]

    raise AssertionError(f"Unclosed function body: {signature}")


def main() -> None:
    view = HISTORY_VIEW.read_text(encoding="utf-8")
    controller = HISTORY_CONTROLLER.read_text(encoding="utf-8")
    store = STORE.read_text(encoding="utf-8")

    failures: list[str] = []

    for signature, source in [
        ("private func addClipEaseTextCard(_ text: String)", view),
        ("private func copyPlainPreviewText(_ text: String?)", controller),
        ("private func copyPreviewFilePaths(for item: ClipboardItem)", controller),
    ]:
        try:
            body = extract_function(source, signature)
        except AssertionError as error:
            failures.append(str(error))
            continue

        skip_index = body.find("store.skipNextClipboardText")
        add_index = body.find("store.addText")
        if skip_index == -1:
            failures.append(f"{signature} must skip the next clipboard monitor text capture")
        if add_index == -1:
            failures.append(f"{signature} must still add one ClipEase-owned history card")
        if skip_index != -1 and add_index != -1 and skip_index > add_index:
            failures.append(f"{signature} must call skipNextClipboardText before addText")

    if "if skippedClipboardTexts.remove(normalizedText) != nil {\n            return\n        }" not in store:
        failures.append("ClipboardHistoryStore.addText must consume skipped text without inserting a second card")

    if failures:
        print("Internal copy skip guard failed:")
        print("\n".join(failures))
        raise SystemExit(1)

    print("OK internal text copies keep one ClipEase card and skip monitor duplicates")


if __name__ == "__main__":
    main()
