#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
COMMAND_FILE = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryCommand.swift"
WINDOW_FILE = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"
MENU_FILE = ROOT / "Sources/ClipEase/App/AppMenuController.swift"

required_command_tokens = [
    "case settings",
    "case edit",
    "case toggleRecording",
    "case preview",
    "case paste",
    "case pastePlainText",
    "case copy",
    "case copyPlainText",
    'displayText: "⌘,"',
    'displayText: "Space"',
    'displayText: "⏎"',
    'displayText: "⇧⏎"',
]

required_window_tokens = [
    ".pastePlainText",
    ".copyPlainText",
    ".historyKeyboardShortcut(.settings)",
    "cardContextMenu(for:",
]

required_menu_tokens = [
    "HistoryCommand.settings.title",
    "HistoryCommand.settings.shortcut",
    "HistoryCommand.newText.title",
    "HistoryCommand.help.title",
    "HistoryCommand.quit.title",
    "HistoryCommand.about.title",
]


def assert_contains(path: Path, tokens: list[str]) -> None:
    text = path.read_text(encoding="utf-8")
    missing = [token for token in tokens if token not in text]
    if missing:
        print(f"{path.relative_to(ROOT)} missing:")
        for token in missing:
            print(f"  - {token}")
        sys.exit(1)


def assert_management_shortcut_removed() -> None:
    text = WINDOW_FILE.read_text(encoding="utf-8")
    command_text = COMMAND_FILE.read_text(encoding="utf-8")
    forbidden = ["toggleManagement", 'keyboardShortcut("m", modifiers: [.command])', "KeyCode.m"]
    combined = text + "\n" + command_text
    found = [token for token in forbidden if token in combined]
    if found:
        print(f"{WINDOW_FILE.relative_to(ROOT)} still contains removed management shortcut tokens:")
        for token in found:
            print(f"  - {token}")
        sys.exit(1)


def main() -> None:
    assert_contains(COMMAND_FILE, required_command_tokens)
    assert_contains(WINDOW_FILE, required_window_tokens)
    assert_contains(MENU_FILE, required_menu_tokens)
    assert_management_shortcut_removed()
    print("history shortcut command constants verified")


if __name__ == "__main__":
    main()
