import AppKit

enum HistoryMenuBuilder {
    static func addMenuItem(_ title: String, to menu: NSMenu, action: @escaping () -> Void) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let target = ClosureMenuItemTarget(action)
        item.target = target
        item.representedObject = target
        item.action = #selector(ClosureMenuItemTarget.performAction)
        menu.addItem(item)
    }
}
