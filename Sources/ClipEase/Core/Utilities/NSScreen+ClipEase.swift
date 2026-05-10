import AppKit

extension NSScreen {
    static var clipeaseScreenContainingMouse: NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return screens.first { screen in
            screen.frame.contains(mouseLocation)
        }
    }
}

