#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SETTINGS_VIEW = ROOT / "Sources/ClipEase/Features/Settings/SettingsView.swift"


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
    settings = SETTINGS_VIEW.read_text(encoding="utf-8")
    about = extract_function(settings, "private var aboutSection: some View")

    required = [
        "private func supportQRCode(",
        "private func supportImage(",
        "supportQRCode(",
        "name: \"Alipay\"",
        "name: \"WeChat\"",
        ".strokeBorder(borderColor, lineWidth: 4)",
        "openSupportCommunity()",
        "Button(\"加入交流群\")",
    ]
    forbidden = [
        "SupportQRCodeSheet",
        "isSupportSheetPresented",
        "Label(\"赞赏支持\"",
        "Button(\"赞赏支持\"",
    ]

    failures: list[str] = []
    for snippet in required:
        if snippet not in settings and snippet not in about:
            failures.append(f"Missing about inline support guard: {snippet}")

    for snippet in forbidden:
        if snippet in settings:
            failures.append(f"Forbidden standalone support UI still present: {snippet}")

    if failures:
        print("About support inline guard failed:")
        print("\n".join(failures))
        raise SystemExit(1)

    print("OK about page embeds support QR codes and removes donate button")


if __name__ == "__main__":
    main()
