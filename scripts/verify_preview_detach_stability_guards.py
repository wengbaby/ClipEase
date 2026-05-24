#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / "Sources/ClipEase/Features/HistoryWindow/HistoryPreviewWindowController.swift").read_text()

required = [
    "finishDetachedPreviewDrag(panel: NSPanel, configuration: PreviewContentConfiguration)",
    "try? await Task.sleep(nanoseconds: 40_000_000)",
    "self.detachedPanels[panelID] === panel",
    "showsArrow: false",
    "private func dragDetachedPreview(_ panel: NSPanel) -> PreviewHeaderDragCompletion",
    "return self.dragDetachedPreview(panel)",
    "dragPanel.performDrag(with: initialMouseDownEvent)",
]

missing = [snippet for snippet in required if snippet not in source]
if missing:
    raise SystemExit("Preview detach stability guard failed. Missing: " + ", ".join(missing))

function_start = source.index("    private func finishDetachedPreviewDrag")
function_end = source.index("    private func closeDetachedPreview", function_start)
body = source[function_start:function_end]
render_index = body.find("self.renderPreviewContent(")
sleep_index = body.find("try? await Task.sleep(nanoseconds: 40_000_000)")
if render_index == -1 or sleep_index == -1 or render_index < sleep_index:
    raise SystemExit("Detached preview content must be rebuilt after the drag-settle delay.")

if "onDetachDrag: { nil }" in body:
    raise SystemExit("Detached preview must keep a reusable drag handler after the first detach.")

detach_start = source.index("    private func detachCurrentPreview")
detach_end = source.index("    private func dragDetachedPreview", detach_start)
detach_body = source[detach_start:detach_end]
if "setFrame(detachedFrame" in detach_body:
    raise SystemExit("Detached preview must not move or shrink before the first system drag starts.")

print("Preview detach stability guard passed.")
