#!/usr/bin/env python3
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOUND_PLAYER = ROOT / "Sources/ClipEase/Core/Utilities/ClipEaseSoundPlayer.swift"
PASTE_EXECUTOR = ROOT / "Sources/ClipEase/Features/PasteExecutor/PasteExecutor.swift"
WINDOW_VIEW = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"
WINDOW_CONTROLLER = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift"
POPOVER = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryPreviewPopoverView.swift"
BUILD_APP = ROOT / "scripts/build-app.sh"
SOUNDS_DIR = ROOT / "Resources/Sounds"


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    sys.exit(1)


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def main() -> None:
    sound_player = SOUND_PLAYER.read_text(encoding="utf-8")
    paste_executor = PASTE_EXECUTOR.read_text(encoding="utf-8")
    window_view = WINDOW_VIEW.read_text(encoding="utf-8")
    window_controller = WINDOW_CONTROLLER.read_text(encoding="utf-8")
    popover = POPOVER.read_text(encoding="utf-8")
    build_app = BUILD_APP.read_text(encoding="utf-8")

    require((SOUNDS_DIR / "Copy.aiff").is_file(), "Copy.aiff must be stored in project resources")
    require((SOUNDS_DIR / "Paste.aiff").is_file(), "Paste.aiff must be stored in project resources")
    require("/Applications/Paste.app" not in sound_player,
            "sound player must use bundled project resources, not external Paste.app files")
    require('subdirectory: "Sounds"' in sound_player,
            "sound player must load Copy/Paste from the app bundle Sounds directory")
    require('cp -R "$ROOT_DIR/Resources/Sounds" "$RESOURCES_DIR/Sounds"' in build_app,
            "build script must copy bundled sounds into the app resources")

    require("soundPlayer.playCopyFeedback()" in paste_executor,
            "PasteExecutor must play copy feedback when auto-paste cannot run")
    require("soundPlayer.playPasteFeedback()" in paste_executor,
            "PasteExecutor must play paste feedback after sending Command+V")
    require(window_view.count("ClipEaseSoundPlayer.shared.playCopyFeedback()") >= 10,
            "main window direct copy actions must play copy feedback")
    require(window_controller.count("ClipEaseSoundPlayer.shared.playCopyFeedback()") >= 3,
            "preview window copy actions must play copy feedback")
    require("ClipEaseSoundPlayer.shared.playCopyFeedback()" in popover,
            "OCR badge copy actions must play copy feedback")

    print("OK sound feedback guards passed")


if __name__ == "__main__":
    main()
