import AppKit

@main
struct PanelDismissalTests {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        let center = NotificationCenter()
        let workspace = NotificationCenter()
        var registered = 0
        var removed = 0
        var local: ((NSEvent) -> NSEvent?)?
        var global: ((NSEvent) -> Void)?
        let source = PanelDismissalMonitor.EventSource(
            global: { global = $0; registered += 1; return registered },
            local: { local = $0; registered += 1; return registered },
            remove: { _ in removed += 1 }
        )
        let panel = NSPanel(contentRect: NSRect(x: 400, y: 400, width: 420, height: 380),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let child = NSPanel(contentRect: NSRect(x: 200, y: 400, width: 160, height: 200),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.addChildWindow(child, ordered: .above)
        var modal: NSWindow?
        let monitor = PanelDismissalMonitor(source: source, notifications: center, workspace: workspace,
                                            windows: { [panel, child] }, modalWindow: { modal })
        var dismissals = 0
        func start() { monitor.start(window: panel) { dismissals += 1 } }
        for cycle in 0..<100 {
            start()
            let before = registered
            start()
            precondition(before == registered, "Repeated layout must not duplicate monitors")
            monitor.receiveClick(at: NSPoint(x: 500, y: 500), localWindow: panel, isLocal: true)
            monitor.receiveClick(at: NSPoint(x: 220, y: 450), localWindow: child, isLocal: true)
            // Settings, menus and input controls are app-local even outside the island.
            precondition(dismissals == cycle)
            let event = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 10, y: 10),
                                           modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
                                           context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            precondition(local?(event) === event, "Internal controls receive the original event")
            let oldGlobal = global
            // Negative screen coordinates cover clicks on a display left of the main display.
            monitor.receiveClick(at: NSPoint(x: -1200, y: 900), localWindow: nil, isLocal: false)
            monitor.receiveClick(at: NSPoint(x: 30, y: 30), localWindow: nil, isLocal: false)
            oldGlobal?(event)
            precondition(dismissals == cycle + 1, "Outside click dismisses exactly once")
            precondition(!monitor.isMonitoring && registered == removed)
        }
        start()
        let menu = NSMenu()
        center.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        monitor.receiveClick(at: .zero, localWindow: nil, isLocal: true)
        precondition(monitor.isMonitoring && monitor.protectsInteraction(at: .zero))
        center.post(name: NSMenu.didEndTrackingNotification, object: menu)
        monitor.receiveClick(at: .zero, localWindow: nil, isLocal: true)
        precondition(!monitor.isMonitoring)

        start()
        modal = child
        monitor.receiveClick(at: NSPoint(x: 220, y: 450), localWindow: nil, isLocal: false)
        precondition(monitor.isMonitoring, "XPC-backed modal open-panel interaction is protected")
        modal = nil
        monitor.receiveClick(at: NSPoint(x: 220, y: 450), localWindow: nil, isLocal: false)
        precondition(!monitor.isMonitoring, "External clicks are not protected by an unrelated app window")

        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.screensDidSleepNotification] {
            start()
            workspace.post(name: name, object: nil)
            precondition(!monitor.isMonitoring)
        }
        start()
        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        precondition(!monitor.isMonitoring, "Cmd-Tab/focus changes dismiss without a mouse event")
        start()
        monitor.receiveActivation(processIdentifier: ProcessInfo.processInfo.processIdentifier)
        precondition(monitor.isMonitoring, "Activating our Settings window is not outside activation")
        monitor.receiveActivation(processIdentifier: -1)
        precondition(!monitor.isMonitoring, "Other-app activation dismisses a nonactivating panel")
        start()
        center.post(name: NSWindow.willCloseNotification, object: panel)
        precondition(!monitor.isMonitoring && registered == removed)
        start()
        let staleLocal = local
        monitor.stop()
        start()
        let outside = NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: -100, y: -100),
                                         modifierFlags: [], timestamp: 0, windowNumber: 0,
                                         context: nil, eventNumber: 2, clickCount: 1, pressure: 1)!
        _ = staleLocal?(outside)
        precondition(monitor.isMonitoring, "Queued events from a previous presentation are ignored")
        _ = local?(outside)
        precondition(!monitor.isMonitoring && registered == removed)
        panel.removeChildWindow(child)
        panel.orderOut(nil)
        child.orderOut(nil)
        print("PASS: 100 outside-click cycles; local controls/child windows; menus; activation; Spaces; sleep; stale callbacks; monitor lifecycle")
    }
}
