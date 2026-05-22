#!/usr/bin/env python3
from pathlib import Path


root = Path(__file__).resolve().parents[1]
history_window = root / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"
settings_view = root / "Sources/ClipEase/Features/Settings/SettingsView.swift"

history_window_text = history_window.read_text(encoding="utf-8")
settings_view_text = settings_view.read_text(encoding="utf-8")

forbidden_history_window = [
    'NSMenuItem(title: "开发测试"',
    "makeDebugNSMenu()",
    "private func makeDebugNSMenu()",
    "addDebugTextItems(count:",
    "clearDebugTextItems()",
]

failures: list[str] = []
for snippet in forbidden_history_window:
    if snippet in history_window_text:
        failures.append(f"HistoryWindowView still exposes debug menu code: {snippet}")

required_settings = [
    "if isDebugToolsVisible",
    "debugDataSection",
    "store.addDebugTextItems(count: 1_000)",
    "store.addDebugTextItems(count: 10_000)",
    "store.clearDebugTextItems()",
]

for snippet in required_settings:
    if snippet not in settings_view_text:
        failures.append(f"Settings hidden debug data entry missing: {snippet}")

if failures:
    print("Visible debug menu guard failed:")
    print("\n".join(failures))
    raise SystemExit(1)

print("OK visible debug menu removed; hidden settings test data entry preserved")
