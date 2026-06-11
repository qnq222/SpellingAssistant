import AppKit

struct PopupPositioningService {
    func frameNearMouse(size: NSSize) -> NSRect {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let padding: CGFloat = 12

        var origin = NSPoint(x: mouseLocation.x - size.width / 2, y: mouseLocation.y + 18)
        if origin.x < visibleFrame.minX + padding {
            origin.x = visibleFrame.minX + padding
        }
        if origin.x + size.width > visibleFrame.maxX - padding {
            origin.x = visibleFrame.maxX - size.width - padding
        }
        if origin.y + size.height > visibleFrame.maxY - padding {
            origin.y = mouseLocation.y - size.height - 18
        }
        if origin.y < visibleFrame.minY + padding {
            origin.y = visibleFrame.minY + padding
        }

        return NSRect(origin: origin, size: size)
    }
}
