#!/usr/bin/env python3
from pathlib import Path


root = Path(__file__).resolve().parents[1]
view = root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"
view_text = view.read_text(encoding="utf-8")


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


try:
    history_card = extract_function(view_text, "private func historyCard(_ item: HistoryPreviewItem)")
except AssertionError as error:
    print(f"History card selection clip guard failed:\n{error}")
    raise SystemExit(1)

required = [
    ".strokeBorder(",
    "isSelected ? Color(red: 0.18, green: 0.55, blue: 1.0) : (isHovered || isPressed ? Color.clear : Color.black.opacity(0.08))",
    "let cardScale: CGFloat = isPressed ? 1.045 : (isHovered ? 1.04 : (isSelected ? 1.025 : 1))",
    ".scaleEffect(cardScale, anchor: .center)",
    ".zIndex(isPressed ? 4 : (isHovered ? 3 : (isSelected ? 2 : 0)))",
]

forbidden = [
    ".stroke(\n                    isSelected ? Color(red: 0.18, green: 0.55, blue: 1.0) : Color.black.opacity(0.08),",
    ".scaleEffect(isSelected ? 1.015 : 1)",
    ".scaleEffect(1)",
]

missing = [snippet for snippet in required if snippet not in history_card]
present_forbidden = [snippet for snippet in forbidden if snippet in history_card]

if missing or present_forbidden:
    if missing:
        print("Missing selected-card clipping guard(s):")
        print("\n".join(missing))
    if present_forbidden:
        print("Forbidden outside selection drawing present:")
        print("\n".join(present_forbidden))
    raise SystemExit(1)

print("OK selected card draws inside its bounds")
