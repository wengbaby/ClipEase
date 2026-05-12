#!/usr/bin/env python3
import plistlib
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    sys.exit(1)


def ok(message: str) -> None:
    print(f"OK: {message}")


def require_file(path: str) -> Path:
    file_path = ROOT / path
    if not file_path.is_file():
        fail(f"Missing file: {path}")
    ok(f"Found {path}")
    return file_path


def require_text(path: str, patterns: list[str]) -> None:
    file_path = require_file(path)
    text = file_path.read_text(encoding="utf-8")
    for pattern in patterns:
        if pattern not in text:
            fail(f"{path} missing text: {pattern}")
    ok(f"{path} contains required markers")


def check_info_plist() -> None:
    info_path = require_file("Resources/Info.plist")
    with info_path.open("rb") as file:
        info = plistlib.load(file)

    short_version = info.get("CFBundleShortVersionString", "")
    build_version = info.get("CFBundleVersion", "")
    if not re.fullmatch(r"\d+\.\d+\.\d+", short_version):
        fail(f"Invalid CFBundleShortVersionString: {short_version}")
    if not re.fullmatch(r"\d{6}\.\d{4}", build_version):
        fail(f"Invalid CFBundleVersion timestamp: {build_version}")
    if info.get("LSUIElement") is not True:
        fail("LSUIElement must be true for menu bar only mode")
    if info.get("CFBundleExecutable") != "ClipEase":
        fail("CFBundleExecutable must be ClipEase")

    ok(f"Version {short_version}({build_version}) is valid")


def check_app_bundle_if_present() -> None:
    app_path = ROOT / ".build/ClipEase.app"
    if not app_path.exists():
        print("SKIP: .build/ClipEase.app not found; run scripts/build-app.sh first")
        return

    require_file(".build/ClipEase.app/Contents/Info.plist")
    executable = ROOT / ".build/ClipEase.app/Contents/MacOS/ClipEase"
    if not executable.is_file():
        fail("Missing app executable in .build/ClipEase.app")
    if not executable.stat().st_mode & 0o111:
        fail("App executable is not executable")
    ok("App bundle structure is valid")


def check_release_docs() -> None:
    require_file("docs/RELEASE_NOTES.md")
    require_file("docs/KNOWN_ISSUES.md")
    checklist = require_file("docs/FIRST_VERSION_TEST_CHECKLIST.md")
    text = checklist.read_text(encoding="utf-8")
    required_sections = [
        "## 1. 启动与窗口",
        "## 2. 剪贴板记录",
        "## 3. 卡片操作",
        "## 4. 搜索与筛选",
        "## 5. 预览",
        "## 6. 新建文本",
        "## 7. 设置页",
        "## 8. 数据维护",
        "## 9. 性能",
        "## 10. 发布前",
    ]
    for section in required_sections:
        if section not in text:
            fail(f"Release checklist missing section: {section}")
    ok("Release checklist has required sections")


def check_key_sources() -> None:
    require_text(
        "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift",
        [
            "HistoryScrollCoordinator",
            "revealPartiallyVisibleCardIfNeeded",
            "previewState.isVisible",
        ],
    )
    require_text(
        "Sources/ClipEase/Features/HistoryWindow/HistoryPreviewWindowController.swift",
        [
            "previewSize(for item",
            "imagePreviewSize",
            "scheduleContentLoad",
        ],
    )
    require_text(
        "Sources/ClipEase/Features/RichTextEditor/RichTextEditorController.swift",
        [
            "performKeyEquivalent",
            "onCommandW",
            "onClose",
        ],
    )
    require_text(
        "Sources/ClipEase/Core/Utilities/URLParser.swift",
        [
            "http://",
            "https://",
            "isIPv4Address",
        ],
    )


def main() -> None:
    check_info_plist()
    check_release_docs()
    check_key_sources()
    check_app_bundle_if_present()
    ok("Smoke check passed")


if __name__ == "__main__":
    main()
