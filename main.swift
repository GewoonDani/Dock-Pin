import AppKit
import ApplicationServices
import ServiceManagement

private let dockMoveEventTag: Int64 = 0x446F636B50696E

func dockMoveEventSource() -> CGEventSource? {
    guard let source = CGEventSource(stateID: .privateState) else { return nil }
    // Synthetic movement must never suppress real mouse or keyboard input.
    source.localEventsSuppressionInterval = 0
    source.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval)
    source.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateRemoteMouseDrag)
    return source
}

func dockMoveEvent(to point: CGPoint, deltaY: Int64, source: CGEventSource) -> CGEvent? {
    guard let event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else { return nil }
    event.setIntegerValueField(.mouseEventDeltaY, value: deltaY)
    event.setIntegerValueField(.eventSourceUserData, value: dockMoveEventTag)
    return event
}

func startAtLoginState(_ status: SMAppService.Status) -> NSControl.StateValue {
    switch status {
    case .enabled: return .on
    case .requiresApproval: return .mixed
    default: return .off
    }
}

if CommandLine.arguments.contains("--self-test") {
    let a = DisplayArea(key: "a", bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
    let b = DisplayArea(key: "b", bounds: CGRect(x: -100, y: -50, width: 100, height: 150))
    let edge = CGPoint(x: -50, y: 99)
    assert(guardedPoint(edge, deltaY: 1, displays: [a, b], selected: "a").y == 97)
    assert(guardedPoint(edge, deltaY: 1, displays: [a, b], selected: "b") == edge)
    assert(guardedPoint(edge, deltaY: 1, displays: [a, b], selected: "missing") == edge)
    let interior = CGPoint(x: -50, y: 90)
    assert(guardedPoint(interior, deltaY: 1, displays: [a, b], selected: "a") == interior)
    let below = DisplayArea(key: "c", bounds: CGRect(x: -100, y: 100, width: 100, height: 100))
    assert(guardedPoint(edge, deltaY: 1, displays: [a, b, below], selected: "a") == edge)
    let mainEdge = CGPoint(x: 50, y: 99)
    assert(guardedPoint(mainEdge, deltaY: 1, displays: [a, b], selected: "a") == mainEdge)
    assert(guardedPoint(CGPoint(x: 500, y: 500), deltaY: 1, displays: [a, b], selected: "a") == CGPoint(x: 500, y: 500))
    assert(guardedPoint(edge, deltaY: -1, displays: [a, b], selected: "a") == edge)
    assert(guardedPoint(edge, deltaY: 0, displays: [a, b], selected: "a").y == 97)
    for _ in 0..<1_000 {
        assert(guardedPoint(edge, deltaY: 100, displays: [a, b], selected: "a").y == 97)
    }
    assert(guardedPoint(edge, deltaY: -1, displays: [a, b], selected: "a") == edge)
    print("11 edge-policy checks passed (including 1,000 fast downward events followed by escape)")
    assert(dockTriggerPoint(displays: [a, b], selected: "b") == CGPoint(x: -50, y: 99))
    assert(dockTriggerPoint(displays: [a, b], selected: "missing") == nil)
    assert(dockTriggerPoint(displays: [a, b, below], selected: "b") == nil)
    let partialBelow = DisplayArea(key: "partial", bounds: CGRect(x: -100, y: 100, width: 75, height: 100))
    assert(dockTriggerPoint(displays: [a, b, partialBelow], selected: "b") == CGPoint(x: -12.5, y: 99))
    let eventSource = dockMoveEventSource()!
    assert(eventSource.localEventsSuppressionInterval == 0)
    assert(eventSource.getLocalEventsFilterDuringSuppressionState(.eventSuppressionStateSuppressionInterval) == [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents])
    assert(eventSource.getLocalEventsFilterDuringSuppressionState(.eventSuppressionStateRemoteMouseDrag) == [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents])
    let move = dockMoveEvent(to: edge, deltaY: 8, source: eventSource)!
    assert(move.type == .mouseMoved && move.location == edge)
    assert(move.getIntegerValueField(.mouseEventDeltaY) == 8)
    assert(move.getIntegerValueField(.eventSourceUserData) == dockMoveEventTag)
    let restore = dockMoveEvent(to: mainEdge, deltaY: 0, source: eventSource)!
    assert(restore.location == mainEdge && restore.getIntegerValueField(.mouseEventDeltaY) == 0)
    assert(restore.getIntegerValueField(.eventSourceUserData) == dockMoveEventTag)
    print("9 Dock move checks passed")
    DockPin.checkInputSafety()
    for active in [false, true] {
        let icon = menuBarIcon(active: active)
        assert(icon.isTemplate && icon.size == NSSize(width: 22, height: 18))
        assert(icon.tiffRepresentation != nil)
        let bitmap = NSBitmapImageRep(data: icon.tiffRepresentation!)!
        assert(bitmap.colorAt(x: bitmap.pixelsWide * 9 / 22, y: bitmap.pixelsHigh * 10 / 18)!.alphaComponent > 0.9)
        let lockAlpha = bitmap.colorAt(x: bitmap.pixelsWide * 19 / 22, y: bitmap.pixelsHigh * 6 / 18)!.alphaComponent
        assert(active ? lockAlpha > 0.9 : lockAlpha == 0)
    }
    print("2 menu bar icon checks passed")
    assert(startAtLoginState(.enabled) == .on)
    assert(startAtLoginState(.requiresApproval) == .mixed)
    assert(startAtLoginState(.notRegistered) == .off)
    assert(startAtLoginState(.notFound) == .off)
    print("4 start-at-login status checks passed")
    exit(0)
}

final class DockPin: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var status: NSStatusItem!
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var dockMove: (timer: Timer, origin: CGPoint, source: CGEventSource)?
    private var displays: [DisplayArea] = []
    private var names: [String: String] = [:]
    private var selected = UserDefaults.standard.string(forKey: "selectedDisplay") ?? ""
    private var enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true
    private var active = false
    private var tapFailed = false
    private var reason = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = ""
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    @objc private func refresh() {
        displays = NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = CGDirectDisplayID(number.uint32Value)
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
            let key = CFUUIDCreateString(nil, uuid)! as String
            names[key] = screen.localizedName
            return DisplayArea(key: key, bounds: CGDisplayBounds(id))
        }
        if selected.isEmpty, let first = displays.first {
            selected = first.key
            UserDefaults.standard.set(selected, forKey: "selectedDisplay")
        }
        if !enabled { reason = "Paused" }
        else if tapFailed { reason = "Mouse filter stopped for safety; restart Dock Pin" }
        else if !AXIsProcessTrusted() { reason = "Accessibility permission required" }
        else if displays.count < 2 { reason = "Only one display connected" }
        else if !displays.contains(where: { $0.key == selected }) { reason = "Selected display disconnected" }
        else if (UserDefaults.standard.persistentDomain(forName: "com.apple.dock")?["orientation"] as? String ?? "bottom") != "bottom" { reason = "Move the Dock to the bottom first" }
        else { reason = "" }
        active = reason.isEmpty
        if !active { stopDockMove(restore: true) }
        if active && tap == nil { installTap() }
        if active && tap == nil { active = false; reason = "Mouse filter unavailable; restart Dock Pin" }
        status.button?.image = menuBarIcon(active: active)
        status.button?.setAccessibilityLabel("Dock Pin")
        status.button?.toolTip = active ? "Dock Pin active: \(names[selected] ?? "display")" : "Dock Pin: \(reason)"
    }

    private func installTap() {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                                    .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<DockPin>.fromOpaque(info).takeUnretainedValue()
            return owner.filterEvent(type, event: event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return }
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func filterEvent(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent> {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Leave macOS's safety shutdown intact instead of repeatedly re-enabling a failing tap.
            tapFailed = true
            active = false
            stopDockMove(restore: false)
            return Unmanaged.passUnretained(event)
        }
        // Our summon and return events must retain their exact positions, including at guarded edges.
        if event.getIntegerValueField(.eventSourceUserData) == dockMoveEventTag {
            return Unmanaged.passUnretained(event)
        }
        stopDockMove(restore: false)
        if active && [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged].contains(type) {
            let point = guardedPoint(event.location, deltaY: event.getIntegerValueField(.mouseEventDeltaY), displays: displays, selected: selected)
            if point != event.location {
                // Correct the event in place; a separate cursor warp can interfere with incoming movement.
                event.location = point
            }
        }
        return Unmanaged.passUnretained(event)
    }

    static func checkInputSafety() {
        let owner = DockPin()
        owner.displays = [DisplayArea(key: "selected", bounds: CGRect(x: 0, y: 0, width: 100, height: 100)),
                          DisplayArea(key: "other", bounds: CGRect(x: 100, y: 0, width: 100, height: 100))]
        owner.selected = "selected"
        let point = CGPoint(x: 150, y: 99)
        let source = dockMoveEventSource()!
        for type: CGEventType in [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                                 .otherMouseDown, .otherMouseUp, .scrollWheel, .keyDown, .keyUp, .flagsChanged] {
            owner.active = true
            let event = CGEvent(source: source)!
            event.type = type
            event.location = point
            assert(owner.filterEvent(type, event: event).takeUnretainedValue() === event)
            assert(event.type == type && event.location == point)
        }
        for type: CGEventType in [.tapDisabledByTimeout, .tapDisabledByUserInput] {
            owner.active = true
            owner.tapFailed = false
            let timer = Timer(timeInterval: 1, repeats: true) { _ in assertionFailure("Cancelled Dock move ran") }
            RunLoop.main.add(timer, forMode: .common)
            owner.dockMove = (timer, point, source)
            let event = CGEvent(source: source)!
            assert(owner.filterEvent(type, event: event).takeUnretainedValue() === event)
            assert(owner.tapFailed && !owner.active && owner.dockMove == nil && !timer.isValid)
            event.type = .mouseMoved
            event.location = point
            event.setIntegerValueField(.mouseEventDeltaY, value: 1)
            _ = owner.filterEvent(.mouseMoved, event: event)
            assert(event.location == point)
        }
        print("Input safety checks passed (suppression, click/key passthrough, and both tap shutdowns)")
    }

    func menuWillOpen(_ menu: NSMenu) {
        stopDockMove(restore: true)
        refresh()
        menu.removeAllItems()
        let header = menu.addItem(withTitle: active ? "Dock protection active" : reason, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(.separator())
        for (index, display) in displays.enumerated() {
            let item = menu.addItem(withTitle: "\(index + 1). \(names[display.key] ?? "Display")", action: #selector(selectDisplay(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = display.key
            item.state = selected == display.key ? .on : .off
        }
        menu.addItem(.separator())
        add(menu, enabled ? "Pause" : "Resume", #selector(toggle))
        let loginStatus = SMAppService.mainApp.status
        let loginItem = menu.addItem(withTitle: loginStatus == .requiresApproval ? "Start at Login (Approval Required)…" : "Start at Login", action: #selector(toggleStartAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = startAtLoginState(loginStatus)
        add(menu, "Set Up Accessibility…", #selector(permissions))
        add(menu, "How It Works", #selector(help))
        menu.addItem(.separator())
        add(menu, "Quit Dock Pin", #selector(quit), key: "q")
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
    }

    @objc private func selectDisplay(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        selected = key
        UserDefaults.standard.set(key, forKey: "selectedDisplay")
        refresh()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.selected == key else { return }
            self.moveDockToSelectedDisplay()
        }
    }

    private func moveDockToSelectedDisplay() {
        stopDockMove(restore: true)
        guard active else { help(); return }
        guard let target = dockTriggerPoint(displays: displays, selected: selected) else {
            let alert = NSAlert()
            alert.messageText = "This display has no free bottom edge"
            alert.informativeText = "Another display is directly below it. Adjust the display arrangement or choose another display."
            alert.runModal()
            return
        }
        guard let origin = CGEvent(source: nil)?.location,
              let source = dockMoveEventSource(),
              !CGEventSource.buttonState(.combinedSessionState, button: .left),
              !CGEventSource.buttonState(.combinedSessionState, button: .right),
              !CGEventSource.buttonState(.combinedSessionState, button: .center) else { return }
        let key = selected
        var step = 0
        // shortcut: emulate the bottom-edge gesture for 1.2 seconds; custom Dock delays may need a longer dwell.
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.active, self.selected == key,
                  dockTriggerPoint(displays: self.displays, selected: key) == target,
                  step < 24 else { self.stopDockMove(restore: true); return }
            let point = step == 0 ? CGPoint(x: target.x, y: target.y - 12) : target
            guard let event = dockMoveEvent(to: point, deltaY: step == 0 ? 0 : 8, source: source) else {
                self.stopDockMove(restore: true)
                return
            }
            event.post(tap: .cghidEventTap)
            step += 1
        }
        dockMove = (timer, origin, source)
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopDockMove(restore: Bool) {
        guard let move = dockMove else { return }
        dockMove = nil
        move.timer.invalidate()
        if restore && displays.contains(where: { $0.bounds.contains(move.origin) }) {
            // Restore the cursor itself; a zero-delta event alone may leave it at the Dock.
            CGWarpMouseCursorPosition(move.origin)
            dockMoveEvent(to: move.origin, deltaY: 0, source: move.source)?.post(tap: .cghidEventTap)
        }
    }

    @objc private func toggle() {
        enabled.toggle()
        UserDefaults.standard.set(enabled, forKey: "enabled")
        refresh()
    }

    @objc private func permissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func toggleStartAtLogin() {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled:
                try service.unregister()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            default:
                try service.register()
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change Start at Login"
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func help() {
        let alert = NSAlert()
        alert.messageText = "Keep the Dock on \(names[selected] ?? "your selected display")"
        alert.informativeText = "Position the Dock at the bottom. Grant Dock Pin access in Privacy & Security → Accessibility. Choose a display in the menu to bring the Dock there automatically while protection is active. The pointer briefly visits its bottom edge and returns; moving, clicking, or scrolling cancels this.\n\nDock Pin guards the bottom 2 points on other displays. Pause the app whenever you need to reach them.\n\nmacOS may still move the Dock after sleep or display changes. Choose your display again, or hold the pointer at its bottom edge until the Dock appears. Protection pauses automatically when the selected display is disconnected."
        NSApp.activate(ignoringOtherApps: true)
        alert.addButton(withTitle: "Got It")
        alert.runModal()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        stopDockMove(restore: true)
        timer?.invalidate()
        if let tap { CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    }
}

let app = NSApplication.shared
let delegate = DockPin()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
