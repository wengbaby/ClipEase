#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
controller = (root / "Sources/ClipEase/Features/HistoryWindow/HistoryPreviewWindowController.swift").read_text()

required = [
    "import QuartzCore",
    "private let bloomOpenDuration: TimeInterval = 0.34",
    "private let bloomCloseDuration: TimeInterval = 0.22",
    "prepareContentBloomLayer(panel, anchorX: arrowX, isOpening: true)",
    "private func animatePanelOpen(_ panel: NSPanel, animationGeneration: UInt64)",
    "panel.contentView?.animator().alphaValue = 1",
    "panel.contentView?.layer?.transform = CATransform3DIdentity",
    "private func prepareContentBloomLayer(_ panel: NSPanel, anchorX: CGFloat, isOpening: Bool)",
    "let normalizedAnchorX = min(max(anchorX / width, 0.08), 0.92)",
    "updateLayerAnchorPoint(layer, anchorPoint: CGPoint(x: normalizedAnchorX, y: 0))",
    "contentView.alphaValue = isOpening ? 0 : 1",
    "CATransform3DMakeScale(0.12, 0.04, 1)",
    "let bloomAnchorX = contentConfiguration?.arrowX",
    "prepareContentBloomLayer(panel, anchorX: anchorX, isOpening: false)",
    "panel.contentView?.animator().alphaValue = 0",
    "panel.contentView?.layer?.transform = previewBloomCollapsedTransform",
    "panel?.contentView = NSView()",
]

forbidden = [
    "let startFrame = targetFrame.offsetBy",
    "panel.animator().alphaValue",
    "panel.animator().setFrame(targetFrame",
    "panel.contentView = NSView()\n        NSAnimationContext.runAnimationGroup",
    "layer.opacity = isOpening ? 0 : 1",
    "previewZoomScale",
    "CATransform3DMakeScale(previewZoomScale, previewZoomScale, 1)",
    "previewLiftOffset",
    "CATransform3DMakeTranslation(0, -previewLiftOffset, 0)",
    "CATransform3DScale(transform, 0.94, 0.90, 1)",
]

missing = [snippet for snippet in required if snippet not in controller]
present_forbidden = [snippet for snippet in forbidden if snippet in controller]

if missing or present_forbidden:
    if missing:
        print("Missing preview bloom animation guard(s):")
        print("\n".join(missing))
    if present_forbidden:
        print("Forbidden preview animation regression(s):")
        print("\n".join(present_forbidden))
    raise SystemExit(1)

print("OK preview bloom animation guards present")
