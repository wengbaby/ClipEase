#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
VIEW = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowView.swift"
TOAST = ROOT / "Sources/ClipEase/Features/HistoryWindow/GlobalStatusToastController.swift"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        print(f"FAIL: {message}")
        sys.exit(1)


def function_body(text: str, signature: str) -> str:
    start = text.find(signature)
    require(start >= 0, f"missing function: {signature}")
    brace = text.find("{", start)
    require(brace >= 0, f"missing function body: {signature}")
    depth = 0
    for index in range(brace, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[brace + 1:index]
    require(False, f"unterminated function body: {signature}")


def call_count(text: str, callee: str) -> int:
    return len(re.findall(rf"\b{re.escape(callee)}\s*\(", text))


view = read(VIEW)
toast = read(TOAST)

outside_body = function_body(view, "private func closeSearchFromOutsideClick()")
has_content_body = function_body(view, "private var hasSearchContent")
require("!searchText.trimmingCharacters" in has_content_body, "search content must include non-empty search text")
require("!searchTokens.isEmpty" in has_content_body, "search content must include visible filter tokens")
require("searchCriteria.hasActiveFilters" in has_content_body, "search content must include active filters")
require("guard isSearchVisible else" in outside_body, "outside click should only act when search is visible")
require("guard !hasSearchContent else" in outside_body, "outside click with search text, tokens, or filters must keep search open")
require("closeSearch()" in outside_body, "outside click without content must collapse the search field")
require("clearAndCloseSearch()" not in outside_body, "ordinary outside click must not unconditionally clear and close search")

close_search_body = function_body(view, "private func closeSearch()")
require("isSearchVisible = false" in close_search_body, "closeSearch must collapse the search field")
require("searchText = \"\"" not in close_search_body, "closeSearch must not clear search text")
require("searchCriteria = HistorySearchCriteria()" not in close_search_body, "closeSearch must not clear filter criteria")

group_navigation_body = function_body(view, "private func closeSearchForGroupNavigation()")
require("guard isSearchVisible || isSearchActive else" in group_navigation_body, "group navigation should only clear active or visible search")
require("clearAndCloseSearch()" in group_navigation_body, "group navigation with search state must clear and close search")

clear_close_body = function_body(view, "private func clearAndCloseSearch()")
require("searchText = \"\"" in clear_close_body, "clearAndCloseSearch must clear search text")
require("searchCriteria = HistorySearchCriteria()" in clear_close_body, "clearAndCloseSearch must clear filters")
require("selectedSearchTokenKind = nil" in clear_close_body, "clearAndCloseSearch must clear selected token")
require("closeSearch()" in clear_close_body, "clearAndCloseSearch must collapse search after clearing")

search_outside_observer_calls = call_count(view, "SearchOutsideWindowMouseDownObserver")
require(search_outside_observer_calls == 1, "history window should use one window-level outside search observer")
require("GroupMouseDownObserver(onMouseDown: closeSearchForGroupNavigation)" in view, "group navigation should explicitly clear and close active search")

body = function_body(view, "var body: some View")
require("SearchOutsideWindowMouseDownObserver(" in body, "body must attach the window-level outside search observer")
require("hostWindow: hostWindow" in body, "outside search observer must bind to the main history window")
require("excludedFrames: searchInteractionScreenFrames" in body, "outside search observer must receive refreshed exclusion frames")
require("onMouseDown: closeSearchFromOutsideClick" in body, "outside search observer must route ordinary outside clicks to closeSearchFromOutsideClick")
require("GroupRenameOutsideMouseDownObserver(" in body, "body must attach the window-level outside rename observer")
require("isEnabled: groupRenameTargetID != nil" in body, "rename observer must only run while a group is being renamed")
require("onMouseDown: commitPendingRenameIfNeeded" in body, "outside rename clicks must save and close the inline editor")

search_field = view.split("private var searchField: some View", 1)[1].split("private func searchTokenView", 1)[0]
require("focusSearchField()" in search_field, "clicking search field content must keep search open and focused")
require("searchFilterPanel" in search_field, "search field must keep the filter popover attached")
require("SearchOutsideWindowMouseDownObserver" not in search_field, "search field internals must not attach a competing outside observer")

toggle_search_body = function_body(view, "private func toggleSearch()")
require("if isSearchVisible" in toggle_search_body, "search toggle must branch on visible state")
require("clearAndCloseSearch()" in toggle_search_body, "clicking the visible search button must collapse search instead of only clearing filters")
require("openSearch()" in toggle_search_body, "clicking the hidden search button must still open search")

search_toggle_button = view.split("private var searchToggleButton: some View", 1)[1].split("private var newGroupButton", 1)[0]
require("SearchInteractionLiveRegion(" in search_toggle_button, "visible search toggle button must be part of the search interaction region")
require("isActive: isSearchVisible" in search_toggle_button, "search toggle live region should only be active while search is visible")
require("SearchInteractionRegionRegistry.shared.register(view)" in search_toggle_button, "search toggle live region must register with the exclusion registry")
require("SearchInteractionRegionRegistry.shared.unregister(view)" in search_toggle_button, "search toggle live region must unregister from the exclusion registry")

filter_panel = view.split("private var searchFilterPanel: some View", 1)[1].split("private func searchFilterSection", 1)[0]
require("toggleSearchType" in filter_panel and "toggleSearchGroup" in filter_panel, "filter panel content must remain interactive")
require("clearAndCloseSearch()" not in filter_panel, "filter panel clicks must not close search")
require("closeSearchFromOutsideClick" not in filter_panel, "filter panel clicks must not trigger outside-close")

refresh_frames = function_body(view, "private func refreshSearchInteractionScreenFrames()")
require("searchControlScreenFrame.standardized.insetBy(dx: -6, dy: -6)" in refresh_frames, "search exclusion must use the measured control screen frame with a narrow inset")
require("searchInteractionFrames.map" not in refresh_frames, "search exclusion must not expand from stale SwiftUI geometry frames")
require("window.frame.insetBy(dx: -8, dy: -8)" in refresh_frames, "search/filter popover windows must be excluded while presented")

outside_observer = function_body(view, "private struct SearchOutsideWindowMouseDownObserver")
require("let hostWindow: NSWindow?" in outside_observer, "outside observer must accept the main host window")
require("context.coordinator.hostWindow = hostWindow" in outside_observer, "outside observer must update the main host window binding")
require("context.coordinator.isEnabled = isEnabled" in outside_observer, "outside observer must update enabled state")
require("context.coordinator.excludedFrames = excludedFrames" in outside_observer, "outside observer must update excluded frames")
require("excludedFrames.contains" in outside_observer, "outside observer must ignore search control frames")
require("isSearchRelatedPanel(eventWindow)" in outside_observer, "outside observer must ignore search/filter popover windows")
require("SearchInteractionRegionRegistry.shared.contains(screenPoint: screenPoint, in: activeHostWindow)" in outside_observer, "outside observer must check live AppKit search region views")
require("activeHostWindow.frame.contains(screenPoint)" in outside_observer, "ordinary outside screen points must reach the outside close path")

live_region = function_body(view, "private struct SearchInteractionLiveRegion")
require("onRegister" in live_region and "onUnregister" in live_region, "search live region must register and unregister its AppKit view")
registry = function_body(view, "private final class SearchInteractionRegionRegistry")
require("NSHashTable<NSView>.weakObjects()" in registry, "search region registry must keep weak AppKit view references")
require("view.convert(view.bounds, to: nil)" in registry, "search region registry must convert live view bounds through AppKit")
require("window.convertPoint(toScreen:" in registry, "search region registry must compare against screen points")

show_status = function_body(view, "private func showStatus(_ text: String)")
require("statusGeneration &+=" in show_status, "showStatus must preserve generation semantics")
require("statusGeneration == generation" in show_status, "showStatus must preserve stale clear guard")
require("GlobalStatusToastController.shared.show(text, relativeTo: hostWindow)" in show_status, "showStatus must route through global toast controller")
require("HistoryWindowHostWindowReader(window: $hostWindow)" in view, "history view must expose its NSWindow to global toast positioning")
require("overlayStatusToast" not in view, "history window must not render a second local overlay toast")
require(view.count("GlobalStatusToastController.shared.show(") == 1, "status messages should only render through the global toast controller")

redirector = function_body(view, "private func horizontalScrollView(at locationInWindow: NSPoint)")
require("hitTest" in redirector and "isHorizontallyScrollable(scrollView)" in redirector, "wheel redirector must find the actual horizontal scroll view under the pointer")
require("guard scope == .cardRail else" in view, "auxiliary rails must not update card rail coordinator")
require(view.count("HorizontalScrollWheelRedirector(scope: .cardRail)") == 1, "only the main card rail should use cardRail scope")
require(view.count("HorizontalScrollWheelRedirector(scope: .auxiliaryRail)") >= 2, "top/search token rails should remain auxiliary")

require("final class GlobalStatusToastController" in toast, "global toast controller missing")
require("static let shared" in toast, "global toast controller should be shared")
require("styleMask: [.borderless, .nonactivatingPanel]" in toast, "toast must use a borderless nonactivating panel")
require("panel.level = .statusBar" in toast, "toast should appear above the main history window")
require("panel.orderFrontRegardless()" in toast, "toast must show even when another app is frontmost")
require("panel.ignoresMouseEvents = true" in toast, "toast must not steal mouse interaction")
require("isHistoryWindow(parentWindow)" in toast, "toast should only update anchor frames from the main history window")
require("lastHistoryWindowFrame" in toast, "toast should remember the main history window frame for later settings/menu toasts")
require("NSScreen.main" in toast, "toast should have a screen fallback when the main window is hidden")
require("generation == currentGeneration" in toast, "global toast must not let older hides dismiss newer messages")

rename_observer = function_body(view, "private struct GroupRenameOutsideMouseDownObserver")
require("event.window === activeHostWindow" in rename_observer, "rename observer must only react to main history window clicks")
require("isCurrentRenameTextFieldHit(event)" in rename_observer, "rename observer must leave clicks inside the active rename input alone")
require("GroupInlineTextField.InlineNSTextField" in rename_observer, "rename observer must identify the inline rename AppKit text field")
require("textField.isGroupRenameField" in rename_observer, "rename observer must only exclude the active group rename text field")

print("PASS: history window interaction toast static checks")
