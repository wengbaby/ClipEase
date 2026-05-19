#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
WINDOW_VIEW = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"
WINDOW_CONTROLLER = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift"
INPUT_STATE = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowInputState.swift"
PREVIEW_CONTROLLER = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryPreviewWindowController.swift"
APP_MENU = ROOT / "Sources/ClipEase/App/AppMenuController.swift"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        print(f"FAIL: {message}")
        sys.exit(1)


view = read(WINDOW_VIEW)
controller = read(WINDOW_CONTROLLER)
input_state = read(INPUT_STATE)
preview = read(PREVIEW_CONTROLLER)
app_menu = read(APP_MENU)

all_text = "\n".join([view, controller, input_state, preview, app_menu])

for token in [
    "favo" + "rite",
    "favo" + "rited",
    "isFavo" + "rite",
    "收藏",
    "管理模式",
    "批量",
    "多选",
]:
    require(token not in all_text, f"removed UI token returned: {token}")

more_menu_match = re.search(
    r"private var moreMenu: some View \{(?P<body>.*?)private var retentionSettingsMenu",
    view,
    flags=re.S,
)
require(more_menu_match is not None, "could not locate moreMenu body")
more_menu = more_menu_match.group("body")
require('Text("...")' in more_menu, "more button label must be literal ...")
require('Image(systemName: "ellipsis")' not in more_menu, "more button should not use ellipsis icon")
require("retentionSettingsMenu" not in more_menu, "more menu should not duplicate retention state entry")
require("toggleRecording()" not in more_menu, "more menu should not duplicate recording state entry")

toolbar_match = re.search(
    r"private var toolbar: some View \{(?P<body>.*?)private var topTrack",
    view,
    flags=re.S,
)
require(toolbar_match is not None, "could not locate toolbar body")
toolbar = toolbar_match.group("body")
require("statusText" not in toolbar, "toolbar should not render persistent statusText pill")
require("authorizationButton" in toolbar, "toolbar should keep lightweight authorization entry")
require('Text("自动粘贴")' not in toolbar, "toolbar should not render persistent auto paste state")
require('Text("记录中")' not in toolbar and 'Text("已暂停")' not in toolbar, "toolbar should not render persistent recording state")
require("retentionMenu" not in toolbar, "toolbar should not render persistent retention state")

require("GlobalStatusToastController.shared.show(text, relativeTo: hostWindow)" in view, "status toast should render through global toast controller")
require("overlayStatusToast" not in view, "window should not render a duplicate local overlay toast")

show_status_match = re.search(
    r"private func showStatus\(_ text: String\) \{(?P<body>.*?)private func copyStatus",
    view,
    flags=re.S,
)
require(show_status_match is not None, "could not locate showStatus")
show_status = show_status_match.group("body")
require("statusGeneration &+=" in show_status, "showStatus should advance a generation token")
require("statusGeneration == generation" in show_status, "old status tasks must not clear newer toast")

require("SearchOutsideWindowMouseDownObserver" in view, "search should close when clicking non-search content")
require("closeSearchFromOutsideClick" in view, "search outside click close handler missing")

sync_match = re.search(
    r"private func syncLatestItemFocusIfNeeded\(.*?\n    private func fulfillPendingLatestFocusIfPossible",
    view,
    flags=re.S,
)
require(sync_match is not None, "could not locate latest item focus sync block")
sync_block = sync_match.group(0)
require("lastObservedNewestItemID" in sync_block, "latest focus requires last-observed newest guard")
require("selectedItemID = focusCandidateID" in sync_block, "hidden-window new item should be selected in the background before next show")
require("latestPresentedItemTimestamp = newestTimestamp" in sync_block, "latest focus sync should mark current newest timestamp in the background")
require("resetFiltersForLatestItemFocus()" in sync_block, "new clipboard focus should still reset filters")
require("pendingLatestFocusLockID = focusCandidateID" in sync_block, "new clipboard focus should lock the prepared target until measured alignment completes")
require("scrollToItemWhenRendered" in view, "new item focus should scroll only via pending item request")

require(
    "HistoryScrollCoordinator.shared.restoreSavedOffset()" in controller,
    "controller should restore saved horizontal scroll offset on show",
)
require(
    "HistoryScrollCoordinator.shared.saveOffset(0)" in view,
    "explicit new item scroll should reset saved offset only for that request",
)
require("savedOffsetsByScope" in view, "horizontal scroll offset should be remembered per view scope")
require("setScope(selectedGroup.storageValue)" in view, "group/all/pinned view changes should switch scroll scope")
require("HistoryScrollCoordinator.shared.saveOffset(nextX)" in view, "user horizontal scroll should save current scope offset")
require("selectedGroup = .all" in view.split("private func resetFiltersForLatestItemFocus", 1)[1].split("private func restoreSelectionAfterClearingSearch", 1)[0], "new clipboard focus should switch from user group/pinned to all")

require("parentWindow: NSWindow" in preview, "preview show should accept parent window")
require("detachPanelFromParent(panel)" in preview, "preview should detach from parent so content can become key")
require("panel.parent?.removeChildWindow(panel)" in preview, "preview should detach from any previous parent window")
require("onClose: @escaping () -> Void" in preview, "preview internal close should call back to shared close path")
require("closePreview()" in controller and "func windowDidResignKey" in controller, "main window resign should close preview")
require("closePreview()" in controller and "func close()" in controller, "main window close should close preview")
require("panel.orderFrontRegardless()" in preview, "preview should remain frontmost while detached for content interaction")

require("struct HistoryItemFocusRequest" in input_state, "created item focus request type missing")
require("requestItemFocus" in input_state, "created item focus request dispatch missing")
require("onCreateText: (ClipboardGroup.ID?) -> Void" in view, "history view should delegate create text to controller")
require("createTextFromMenu()" in view and "createTextFromShortcut()" in view, "menu and shortcut create text flows missing")
require("createTextFromHistoryWindow(defaultGroupID:" in controller, "controller-owned create text flow missing")
require("showAndFocusCreatedItem" in controller, "created text should reopen and focus history window")
require("item.groupID == nil" in controller, "created text reset-to-all should depend on created item grouping")
require("onCreated?(createdItem)" in app_menu, "AppMenuController should report created rich text item")
require("previousIDs" in app_menu, "created rich text item should be detected without Store write semantic changes")

storage_paths = [
    ROOT / "Sources/ClipEase/Core/Storage",
    ROOT / "Sources/ClipEase/Core/Models/ClipboardItem.swift",
]
for path in storage_paths:
    require(path.exists(), f"expected baseline path missing: {path.relative_to(ROOT)}")

print("PASS: stage 8 window experience static checks")
