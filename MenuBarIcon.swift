import AppKit

func menuBarIcon(active: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
        NSColor.black.set()
        let screen = NSBezierPath(roundedRect: NSRect(x: 1.75, y: 4.75, width: 15.5, height: 10.5), xRadius: 2, yRadius: 2)
        screen.lineWidth = 1.5
        screen.stroke()
        let stand = NSBezierPath()
        stand.move(to: NSPoint(x: 9.5, y: 4))
        stand.line(to: NSPoint(x: 9.5, y: 2))
        stand.move(to: NSPoint(x: 6, y: 1.75))
        stand.line(to: NSPoint(x: 13, y: 1.75))
        stand.lineWidth = 1.5
        stand.lineCapStyle = .round
        stand.stroke()
        let dock = NSBezierPath(roundedRect: NSRect(x: 6, y: 7, width: 7, height: 2), xRadius: 1, yRadius: 1)
        dock.fill()
        guard active else { return true }
        // Clear the monitor behind the lock so the tiny silhouette stays readable.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(roundedRect: NSRect(x: 13, y: 8, width: 9, height: 10), xRadius: 2, yRadius: 2).fill()
        NSGraphicsContext.restoreGraphicsState()
        let shackle = NSBezierPath(roundedRect: NSRect(x: 15.5, y: 11.5, width: 4, height: 5), xRadius: 2, yRadius: 2)
        shackle.lineWidth = 1.5
        shackle.stroke()
        let lock = NSBezierPath(roundedRect: NSRect(x: 14, y: 8.5, width: 7, height: 5.5), xRadius: 1.25, yRadius: 1.25)
        lock.appendOval(in: NSRect(x: 16.75, y: 10.25, width: 1.5, height: 2))
        lock.windingRule = .evenOdd
        lock.fill()
        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = active ? "Dock Pin: protection active" : "Dock Pin: protection inactive"
    return image
}
