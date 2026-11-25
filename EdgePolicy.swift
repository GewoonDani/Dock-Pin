import CoreGraphics

struct DisplayArea {
    let key: String
    let bounds: CGRect
}

func guardedPoint(_ point: CGPoint, displays: [DisplayArea], selected: String) -> CGPoint {
    guard displays.contains(where: { $0.key == selected }),
          let display = displays.first(where: { $0.bounds.contains(point) }),
          display.key != selected,
          point.y >= display.bounds.maxY - 2 else { return point }
    // Keep passage to a display below open; only guard an exposed bottom edge.
    let below = CGPoint(x: point.x, y: display.bounds.maxY + 1)
    guard !displays.contains(where: { $0.bounds.contains(below) }) else { return point }
    return CGPoint(x: point.x, y: display.bounds.maxY - 3)
}
