import AppKit
import ApplicationServices
import ServiceManagement

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
    assert(guardedPoint(edge, displays: [a, b], selected: "a").y == 97)
    assert(guardedPoint(edge, displays: [a, b], selected: "b") == edge)
    assert(guardedPoint(edge, displays: [a, b], selected: "missing") == edge)
    let interior = CGPoint(x: -50, y: 90)
    assert(guardedPoint(interior, displays: [a, b], selected: "a") == interior)
    let below = DisplayArea(key: "c", bounds: CGRect(x: -100, y: 100, width: 100, height: 100))
    assert(guardedPoint(edge, displays: [a, b, below], selected: "a") == edge)
    let mainEdge = CGPoint(x: 50, y: 99)
    assert(guardedPoint(mainEdge, displays: [a, b], selected: "a") == mainEdge)
    assert(guardedPoint(CGPoint(x: 500, y: 500), displays: [a, b], selected: "a") == CGPoint(x: 500, y: 500))
    print("7 edge-policy checks passed")
    for active in [false, true] {
        let icon = menuBarIcon(active: active)
        assert(icon.isTemplate && icon.size == NSSize(width: 22, height: 18))
        assert(icon.tiffRepresentation != nil)
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
    private var displays: [DisplayArea] = []
    private var names: [String: String] = [:]
    private var selected = UserDefaults.standard.string(forKey: "selectedDisplay") ?? ""
    private var enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true
    private var active = false
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
        else if !AXIsProcessTrusted() { reason = "Accessibility permission required" }
        else if displays.count < 2 { reason = "Only one display connected" }
        else if !displays.contains(where: { $0.key == selected }) { reason = "Selected display disconnected" }
        else if (UserDefaults.standard.persistentDomain(forName: "com.apple.dock")?["orientation"] as? String ?? "bottom") != "bottom" { reason = "Move the Dock to the bottom first" }
        else { reason = "" }
        active = reason.isEmpty
        if active && tap == nil { installTap() }
        if active && tap == nil { active = false; reason = "Mouse filter unavailable; restart Dock Pin" }
        status.button?.image = menuBarIcon(active: active)
        status.button?.setAccessibilityLabel("Dock Pin")
        status.button?.toolTip = active ? "Dock Pin active: \(names[selected] ?? "display")" : "Dock Pin: \(reason)"
    }

    private func installTap() {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<DockPin>.fromOpaque(info).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = owner.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            if owner.active {
                let point = guardedPoint(event.location, displays: owner.displays, selected: owner.selected)
                if point != event.location {
                    // shortcut: guard the bottom trigger zone; forced moves after wake need manual repositioning.
                    CGWarpMouseCursorPosition(point)
                    event.location = point
                }
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return }
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func menuWillOpen(_ menu: NSMenu) {
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
        help()
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
        alert.informativeText = "Position the Dock at the bottom. Grant Dock Pin access in Privacy & Security → Accessibility. Then move your pointer to the bottom edge of the selected display and hold it there until the Dock appears.\n\nDock Pin guards the bottom 2 points on other displays. You cannot click or drag all the way to those edges. Pause the app whenever you need to reach them.\n\nmacOS may still move the Dock after sleep or display changes. If that happens, bring it back using the same pointer movement. Protection pauses automatically when the selected display is disconnected."
        NSApp.activate(ignoringOtherApps: true)
        alert.addButton(withTitle: "Got It")
        alert.runModal()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
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
