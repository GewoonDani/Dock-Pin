import CoreGraphics

struct DisplayArea {
    let key: String
    let bounds: CGRect
}

func dockTriggerPoint(displays: [DisplayArea], selected: String) -> CGPoint? {
    guard let display = displays.first(where: { $0.key == selected }) else { return nil }
    let bounds = display.bounds
    let below = displays.filter { $0.key != selected && $0.bounds.minY <= bounds.maxY && $0.bounds.maxY > bounds.maxY }
    let edges = ([bounds.minX, bounds.maxX] + below.flatMap { [$0.bounds.minX, $0.bounds.maxX] })
        .filter { $0 >= bounds.minX && $0 <= bounds.maxX }.sorted()
    let gaps = zip(edges, edges.dropFirst()).sorted { $0.1 - $0.0 > $1.1 - $1.0 }
    for (left, right) in gaps where right - left >= 2 {
        let point = CGPoint(x: (left + right) / 2, y: bounds.maxY - 1)
        if !below.contains(where: { $0.bounds.contains(CGPoint(x: point.x, y: bounds.maxY)) }) {
            return point
        }
    }
    return nil
}

func guardedPoint(_ point: CGPoint, deltaY: Int64, displays: [DisplayArea], selected: String) -> CGPoint {
    // Always let upward movement escape the edge, even if its location is still in the trigger zone.
    guard deltaY >= 0,
          displays.contains(where: { $0.key == selected }),
          let display = displays.first(where: { $0.bounds.contains(point) }),
          display.key != selected,
          point.y >= display.bounds.maxY - 2 else { return point }
    // Keep passage to a display below open; only guard an exposed bottom edge.
    let below = CGPoint(x: point.x, y: display.bounds.maxY + 1)
    guard !displays.contains(where: { $0.bounds.contains(below) }) else { return point }
    return CGPoint(x: point.x, y: display.bounds.maxY - 3)
}
