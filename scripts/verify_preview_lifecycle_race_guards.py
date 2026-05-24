#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / "Sources/ClipEase/Features/HistoryWindow/HistoryPreviewWindowController.swift").read_text()

required = [
    "private var attachedAnimationGeneration: UInt64 = 0",
    "attachedAnimationGeneration &+= 1",
    "let animationGeneration = attachedAnimationGeneration",
    "let shouldAnimateOpen = !isAlreadyVisible || isAttachedClosing",
    "private var isAttachedClosing = false",
    "isAttachedClosing = true",
    "isAttachedClosing = false",
    "guard self?.attachedAnimationGeneration == animationGeneration",
    "panel?.contentView?.alphaValue = 0",
    "panel?.contentView?.layer?.transform = CATransform3DIdentity",
    "panel?.orderOut(nil)",
    "isAttachedClosing = false",
    "private func finishDetachedPreviewDrag(panel: NSPanel, configuration: PreviewContentConfiguration)",
    "panel.contentView = NSHostingView(",
    "if self.detachedPanels[ObjectIdentifier(panel)] === panel",
    "return self.dragDetachedPreview(panel)",
]

missing = [snippet for snippet in required if snippet not in source]
if missing:
    raise SystemExit("Missing preview lifecycle race guard(s):\n" + "\n".join(missing))

close_start = source.index("    func close(allowDetached: Bool)")
close_end = source.index("    func move(anchorScreenPoint:", close_start)
close_body = source[close_start:close_end]

if "guard self?.attachedAnimationGeneration == animationGeneration" not in close_body:
    raise SystemExit("Attached close completion must ignore stale close animations after a new show.")

completion_start = close_body.index("} completionHandler:")
completion_body = close_body[completion_start:]

alpha_zero = completion_body.find("panel?.contentView?.alphaValue = 0")
content_clear = completion_body.find("panel?.contentView = NSView()")
order_out = completion_body.find("panel?.orderOut(nil)")
if min(alpha_zero, content_clear, order_out) == -1:
    raise SystemExit("Attached close completion must hide, clear, and order out the panel.")
if not (alpha_zero < order_out < content_clear):
    raise SystemExit("Attached close completion must hide and order out the old tiny content before clearing it.")

finish_start = source.index("    private func finishDetachedPreviewDrag")
finish_end = source.index("    private func closeDetachedPreview", finish_start)
finish_body = source[finish_start:finish_end]

for forbidden in [
    "Task { @MainActor",
    "try? await Task.sleep",
    "self.renderPreviewContent(",
    "showsArrow: false",
]:
    if forbidden in finish_body:
        raise SystemExit(f"Detached drag release must not rebuild content and flash: {forbidden}")

print("OK preview lifecycle race guards present")
