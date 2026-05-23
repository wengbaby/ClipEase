#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def require(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def main() -> None:
    failures: list[str] = []
    toast = read("Sources/ClipEase/Features/HistoryWindow/GlobalStatusToastController.swift")
    store = read("Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift")
    app_menu = read("Sources/ClipEase/App/AppMenuController.swift")
    history_controller = read("Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift")
    app_delegate = read("Sources/ClipEase/App/AppDelegate.swift")
    guide = read("Sources/ClipEase/Features/Settings/AccessibilityPermissionGuideWindowController.swift")

    require("fallbackHistoryPanelHeight" in toast, "global toast must use a bottom history-window fallback frame", failures)
    require("fallbackHistoryFrame(for:" in toast, "global toast must build a fallback history frame before main window opens", failures)
    require("NSScreen.clipeaseScreenContainingMouse" in toast, "toast fallback should use the mouse screen before NSScreen.main", failures)
    require("screenFrame.maxY - toastSize.height" not in toast, "toast must not fall back to the menu-bar area", failures)

    require("userDefaults.object(forKey: Self.retentionPolicyKey) == nil" in store, "retention default must distinguish unset defaults from raw value 0", failures)
    require("self.retentionPolicy = .sevenDays" in store, "new users must default to seven days", failures)
    require("?? .sevenDays" in store, "invalid retention values should fall back to seven days", failures)
    require("?? .forever" not in store, "retention must not default to forever", failures)

    require("private func closeHistoryWindowIfNeeded()" in app_menu, "menu controller must centralize history window closing", failures)
    require("historyWindowController?.hideImmediatelyForAutoPaste()" in app_menu, "menu/help/settings/about actions must release keyboard monitors immediately", failures)
    require("func showPermissionGuide()" in app_menu, "menu controller must expose the permission guide", failures)
    require("AccessibilityPermissionGuideWindowController" in app_menu, "menu controller must retain the permission guide window", failures)
    require("func makeStatusBarMenu() -> NSMenu {\n        closeHistoryWindowIfNeeded()" in app_menu, "right-click status menu must close the history window before opening", failures)
    require("func createTextItem(" in app_menu and "closeHistoryWindowIfNeeded()\n        let editorController" in app_menu, "new text action must close the history window", failures)
    for action in ["func showHelp()", "func showSettings()", "func showAbout()"]:
        body_start = app_menu.find(action)
        require(body_start >= 0, f"missing {action}", failures)
        if body_start >= 0:
            body = app_menu[body_start:app_menu.find("\n    func ", body_start + 1) if app_menu.find("\n    func ", body_start + 1) != -1 else len(app_menu)]
            require("closeHistoryWindowIfNeeded()" in body, f"{action} must close the history window", failures)

    require("guard accessibilityPermissionState.refresh() else" in history_controller, "history window must gate show/toggle on accessibility permission", failures)
    require("appMenuController.showPermissionGuide()" in history_controller, "history window must open permission guide when unauthorized", failures)
    require("if !accessibilityPermissionState.refresh()" in app_delegate, "launch path must check accessibility permission before preloading history UI", failures)
    require("appMenuController.showPermissionGuide()" in app_delegate, "launch path must show permission guide when unauthorized", failures)

    require("final class AccessibilityPermissionGuideWindowController" in guide, "permission guide controller missing", failures)
    require("AX" not in guide, "permission guide should use AccessibilityPermissionState instead of duplicating AX calls", failures)
    require("permissionState.openSystemSettings()" in guide, "permission guide must open System Settings", failures)
    require("permissionState.revealCurrentAppInFinder()" in guide, "permission guide must expose current app location", failures)
    require("didBecomeActiveNotification" in guide, "permission guide must refresh when returning from System Settings", failures)
    require("onAuthorized()" in guide, "permission guide must close after authorization is detected", failures)

    if failures:
        print("Permission/toast/retention guard failed:")
        print("\n".join(failures))
        raise SystemExit(1)

    print("OK permission guide, toast fallback, retention default, and menu-close guards passed")


if __name__ == "__main__":
    main()
