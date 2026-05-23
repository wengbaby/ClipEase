#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VIEW = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"


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
    view = VIEW.read_text(encoding="utf-8")
    programmatic = extract_function(view, "private func programmaticJumpTargetOffset(for id: HistoryPreviewItem.ID) -> CGFloat?")
    target_frame = extract_function(view, "private func targetScrollOffsetForFocusedFrame(")
    reset_latest = extract_function(view, "private func resetVisibleRailWindowForLatestFocus(_ id: HistoryPreviewItem.ID)")

    required = [
        "private let latestInsertedCardLeadingInset",
        "private func latestInsertedCardPreferredOffset(",
        "frame.minX - latestInsertedCardLeadingInset",
        "max(0, preferredOffset)",
        "latestInsertedCardPreferredOffset(frame: frame)",
        "x: latestInsertedCardPreferredOffset(frame: CGRect(",
    ]

    scoped_required = [
        ("programmaticJumpTargetOffset", programmatic, ["latestInsertedCardPreferredOffset(frame: frame)"]),
        ("targetScrollOffsetForFocusedFrame", target_frame, ["max(0, preferredOffset)"]),
        ("resetVisibleRailWindowForLatestFocus", reset_latest, ["latestInsertedCardPreferredOffset(frame: CGRect("]),
    ]

    forbidden = [
        "let preferredOffset = frame.minX - focusedItemLeadingX(\n            for: id,\n            frame: frame,\n            forceEdgePeekAlignment: true\n        )",
    ]

    failures: list[str] = []
    for snippet in required:
        if snippet not in view:
            failures.append(f"Missing latest-card left padding guard: {snippet}")

    for label, body, snippets in scoped_required:
        for snippet in snippets:
            if snippet not in body:
                failures.append(f"Missing {label} left padding guard: {snippet}")

    for snippet in forbidden:
        if snippet in view:
            failures.append(f"Forbidden latest-card edge alignment: {snippet}")

    if "if isFirstRenderedItem(id) {\n            return 0\n        }" in target_frame:
        failures.append("Forbidden latest-card edge alignment in targetScrollOffsetForFocusedFrame")

    if failures:
        print("Latest card left padding guard failed:")
        print("\n".join(failures))
        raise SystemExit(1)

    print("OK latest card programmatic focus preserves left padding")


if __name__ == "__main__":
    main()
