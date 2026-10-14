import AppKit

/// A transient surface must not depend on becoming key/active to dismiss.
/// Mouse-only monitors require no keyboard-monitoring or Accessibility grant.
@MainActor
final class PanelDismissalMonitor {
    struct EventSource {
        var global: (@escaping (NSEvent) -> Void) -> Any?
        var local: (@escaping (NSEvent) -> NSEvent?) -> Any?
        var remove: (Any) -> Void

        static let appKit = EventSource(
            global: { NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: $0) },
            local: { NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: $0) },
            remove: { NSEvent.removeMonitor($0) }
        )
    }

    private let source: EventSource
    private let notifications: NotificationCenter
    private let workspace: NotificationCenter
    private let windows: @MainActor () -> [NSWindow]
    private let modalWindow: @MainActor () -> NSWindow?
    private var globalToken: Any?
    private var localToken: Any?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private weak var surface: NSWindow?
    private var dismiss: (() -> Void)?
    private var generation = 0
    private var trackingMenus = Set<ObjectIdentifier>()
    private(set) var isMonitoring = false

    init(source: EventSource = .appKit,
         notifications: NotificationCenter = .default,
         workspace: NotificationCenter = NSWorkspace.shared.notificationCenter,
         windows: @escaping @MainActor () -> [NSWindow] = { NSApp.windows },
         modalWindow: @escaping @MainActor () -> NSWindow? = { NSApp.modalWindow }) {
        self.source = source
        self.notifications = notifications
        self.workspace = workspace
        self.windows = windows
        self.modalWindow = modalWindow
    }

    func start(window: NSWindow, dismiss: @escaping () -> Void) {
        if isMonitoring, surface === window { return }
        stop()
        surface = window
        self.dismiss = dismiss
        isMonitoring = true
        let token = generation
        globalToken = source.global { [weak self] event in
            guard let self, self.generation == token else { return }
            // CGEvent coordinates use the main display's top-left origin;
            // AppKit screen coordinates use its bottom-left, including displays
            // above/left of it. Never sample a later cursor position instead.
            guard let location = event.cgEvent?.location,
                  let mainDisplay = NSScreen.screens.first else { return }
            self.receiveClick(at: NSPoint(x: location.x, y: mainDisplay.frame.maxY - location.y),
                              localWindow: nil, isLocal: false)
        }
        localToken = source.local { [weak self] event in
            guard let self, self.generation == token else { return event }
            let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
            self.receiveClick(at: point, localWindow: event.window, isLocal: true)
            return event // Never consume a control's click.
        }
        observe(notifications, NSMenu.didBeginTrackingNotification) { [weak self] note in
            if let menu = note.object as? NSMenu { self?.trackingMenus.insert(ObjectIdentifier(menu)) }
        }
        observe(notifications, NSMenu.didEndTrackingNotification) { [weak self] note in
            if let menu = note.object as? NSMenu { self?.trackingMenus.remove(ObjectIdentifier(menu)) }
        }
        observe(notifications, NSApplication.didResignActiveNotification) { [weak self] _ in self?.requestDismissal() }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.receiveActivation(processIdentifier: app.processIdentifier)
        }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] _ in self?.requestDismissal() }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] _ in self?.requestDismissal() }
        observe(notifications, NSWindow.willCloseNotification) { [weak self] note in
            guard let self, let window = note.object as? NSWindow, window === self.surface else { return }
            self.stop()
        }
    }

    func stop() {
        generation += 1
        isMonitoring = false
        if let globalToken { source.remove(globalToken) }
        if let localToken { source.remove(localToken) }
        globalToken = nil
        localToken = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        trackingMenus.removeAll()
        surface = nil
        dismiss = nil
    }

    /// Menus, sheets, popovers and Settings belong to the app, not the desktop.
    /// Also used by hover-close so moving into a dropdown cannot close its owner.
    func protectsInteraction(at point: NSPoint) -> Bool {
        !trackingMenus.isEmpty || windows().contains {
            $0 !== surface && $0.isVisible && !$0.ignoresMouseEvents && $0.frame.contains(point)
        }
    }

    func receiveClick(at point: NSPoint, localWindow: NSWindow?, isLocal: Bool) {
        guard isMonitoring, let surface else { return }
        // A local event addressed to an app window is authoritative even if a
        // popup extends beyond the island or the panel is changing size.
        if isLocal && (localWindow != nil || !trackingMenus.isEmpty) { return }
        if surface.frame.contains(point) { return }
        // XPC-backed native panels can deliver global events within an app sheet.
        if let sheet = surface.attachedSheet, sheet.isVisible, sheet.frame.contains(point) { return }
        if let modal = modalWindow(), modal.frame.contains(point) { return }
        if isLocal && protectsInteraction(at: point) { return }
        requestDismissal()
    }

    func receiveActivation(processIdentifier: pid_t) {
        guard processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        requestDismissal()
    }

    private func requestDismissal() {
        guard isMonitoring else { return }
        let action = dismiss
        stop() // Disarm before invoking the owner; repeated events are harmless.
        action?()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping (Notification) -> Void) {
        let token = generation
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, self.isMonitoring, self.generation == token else { return }
                action(note)
            }
        }
        observers.append((center, observer))
    }

    deinit {
        // Owners stop on hide/termination; this is a last-resort teardown guard.
        if let globalToken { source.remove(globalToken) }
        if let localToken { source.remove(localToken) }
        for (center, observer) in observers { center.removeObserver(observer) }
    }
}
