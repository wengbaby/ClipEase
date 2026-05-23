#!/usr/bin/env python3
from pathlib import Path


root = Path(__file__).resolve().parents[1]
sound = root / "Sources/ClipEase/Core/Utilities/ClipEaseSoundPlayer.swift"
delegate = root / "Sources/ClipEase/App/AppDelegate.swift"
sound_text = sound.read_text(encoding="utf-8")
delegate_text = delegate.read_text(encoding="utf-8")

required = [
    "func preloadFeedbackSounds()",
    "loadPlayer(.copy)",
    "loadPlayer(.paste)",
    "ClipEaseSoundPlayer.shared.preloadFeedbackSounds()",
]

failures = [snippet for snippet in required if snippet not in sound_text + delegate_text]

if "let player = cachedPlayer ?? loadPlayer(feedbackSound)" not in sound_text:
    failures.append("play path should still use cached player before falling back to load")

if failures:
    print("Sound player preload guard failed:")
    print("\n".join(failures))
    raise SystemExit(1)

print("OK feedback sounds are preloaded before clipboard polling")
