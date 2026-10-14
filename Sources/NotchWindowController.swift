import AppKit
import Combine
import SwiftUI

private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class NotchWindowController {
    private let model: ShelfModel
    private weak var appDelegate: AppDelegate?
    private let panel: NotchPanel
    private var subscriptions = Set<AnyCancellable>()
    private var screenObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var displayAsleep = false

    private var closeTimer: Timer?
    private var openTimer: Timer?
    private var globalMouseDownMonitor: Any?
    private var globalMouseMoveMonitor: Any?
    private var localMouseMonitor: Any?
    private var compactMouseMonitor: Any?
    private let dismissalMonitor = PanelDismissalMonitor()
    private var frameTransition = 0
    private var collapseUntil: TimeInterval = 0
    private var isCollapsing: Bool { ProcessInfo.processInfo.systemUptime < collapseUntil }

    private var collapsedSize = CGSize(width: 200, height: 38)
    private var targetScreen: NSScreen?
    private var collapsedFrame: NSRect = .zero
    private var stateUpdateScheduled = false
    private var isStopped = false

    init(model: ShelfModel, appDelegate: AppDelegate) {
        self.model = model
        self.appDelegate = appDelegate
        panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configurePanel()
        model.$isExpanded.removeDuplicates().sink { [weak appDelegate] expanded in
            if expanded { appDelegate?.dismissFloatingControls() }
        }.store(in: &subscriptions)
        let hostingView = FirstClickHostingView(rootView: NotchView(model: model, appDelegate: appDelegate, preferences: model.preferences))
        // The controller owns window size. SwiftUI must not resize the panel
        // again in response to its intrinsic content size during a transition.
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        Publishers.CombineLatest(model.$isExpanded, model.$activePage)
            .sink { [weak self] _, _ in
                self?.scheduleStateUpdate()
            }
            .store(in: &subscriptions)

        model.$isVisible
            .removeDuplicates()
            .sink { [weak self] visible in
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.isStopped else { return }
                    self.applyVisibility(self.model.isVisible)
                }
            }
            .store(in: &subscriptions)

        model.$showsNowPlaying.removeDuplicates().sink { [weak self] _ in
            self?.scheduleStateUpdate()
        }.store(in: &subscriptions)

        model.preferences.objectWillChange.sink { [weak self] _ in
            self?.openTimer?.invalidate()
            self?.openTimer = nil
            self?.closeTimer?.invalidate()
            self?.closeTimer = nil
            self?.model.stop()
            self?.scheduleStateUpdate()
        }.store(in: &subscriptions)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.selectScreenAndPosition()
            }
        }

        setupMonitors()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.displayAsleep = true
                self?.removeMonitors()
                self?.model.close()
            }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isStopped else { return }
                self.displayAsleep = false
                self.selectScreenAndPosition()
                if self.model.isVisible {
                    self.setupMonitors()
                    self.checkMouseHover()
                }
            }
        })
    }

    func show() {
        selectScreenAndPosition()
        applyVisibility(model.isVisible)
    }

    func orderFront() {
        guard model.isVisible else { return }
        panel.orderFrontRegardless()
    }

    func recoverAfterWake() {
        guard !isStopped else { return }
        displayAsleep = false
        model.resetAfterWake()
        selectScreenAndPosition()
        applyVisibility(model.isVisible)
    }

    func stop() {
        isStopped = true
        subscriptions.removeAll()
        removeMonitors()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers.removeAll()
        panel.orderOut(nil)
    }

    private func configurePanel() {
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .mainMenu + 3
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
    }

    private func setupMonitors() {
        removeMonitors()
        guard !isStopped, !displayAsleep, model.isVisible else { return }

        // Movement delivers the opening signal; no recurring idle polling.
        globalMouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] _ in
            self?.checkMouseHover()
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] event in
            self?.checkMouseHover()
            return event
        }

        updateCompactClickMonitors()
        if model.isExpanded {
            dismissalMonitor.start(window: panel) { [weak self] in self?.dismissExpandedPanel() }
        }
    }

    private func updateCompactClickMonitors() {
        if model.isExpanded || !model.isVisible || displayAsleep || isStopped {
            if let globalMouseDownMonitor { NSEvent.removeMonitor(globalMouseDownMonitor) }
            if let compactMouseMonitor { NSEvent.removeMonitor(compactMouseMonitor) }
            globalMouseDownMonitor = nil
            compactMouseMonitor = nil
            return
        }
        guard globalMouseDownMonitor == nil, compactMouseMonitor == nil else { return }
        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.handleCompactClick()
        }
        compactMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handleCompactClick()
            return event
        }
    }

    private func removeMonitors() {
        dismissalMonitor.stop()
        openTimer?.invalidate()
        openTimer = nil
        model.stop()
        closeTimer?.invalidate()
        closeTimer = nil

        if let globalMouseDownMonitor { NSEvent.removeMonitor(globalMouseDownMonitor) }
        globalMouseDownMonitor = nil
        if let compactMouseMonitor { NSEvent.removeMonitor(compactMouseMonitor) }
        compactMouseMonitor = nil
        if let globalMouseMoveMonitor { NSEvent.removeMonitor(globalMouseMoveMonitor) }
        globalMouseMoveMonitor = nil
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        localMouseMonitor = nil
    }

    private func checkMouseHover() {
        guard model.isVisible, let screen = targetScreen else { return }
        guard !isCollapsing else { return }
        if model.isExpanded && dismissalMonitor.protectsInteraction(at: NSEvent.mouseLocation) {
            reportHover(true)
            return
        }
        if !model.isExpanded && NSEvent.pressedMouseButtons != 0 {
            reportHover(false)
            return
        }
        let mouse = NSEvent.mouseLocation

        if model.isExpanded {
            let expandedBounds = panel.frame
                .insetBy(dx: -4, dy: -4)
            let isInside = expandedBounds.contains(mouse)
            reportHover(isInside)
        } else {
            // Include the topmost coordinate; CGRect.contains excludes maxY.
            // Match the currently drawn collapsed notch, including the small
            // now-playing wings. Never reuse the old expanded window bounds.
            let activationFrame = targetFrame(expanded: false, page: .controls)
            let isInside = mouse.x >= activationFrame.minX
                && mouse.x <= activationFrame.maxX
                && mouse.y >= activationFrame.minY
                && mouse.y <= screen.frame.maxY
            reportHover(isInside)
        }
    }

    private func reportHover(_ inside: Bool) {
        model.reportPointerState(inside: inside)
        if !model.pendingOpen {
            openTimer?.invalidate()
            openTimer = nil
        } else if openTimer == nil {
            // One cancellable deadline; stationary intentional hover opens too.
            let timer = Timer(timeInterval: model.preferences.openingDelay + 0.01, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.openTimer = nil
                    self?.checkMouseHover()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            openTimer = timer
        }
        if inside || !model.isExpanded || model.isManuallyOpened {
            closeTimer?.invalidate()
            closeTimer = nil
        } else if closeTimer == nil {
            // One deadline after exit, including when the pointer stops moving.
            let timer = Timer(timeInterval: model.preferences.closingDelay + 0.01, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.closeTimer = nil
                    self.checkMouseHover()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            closeTimer = timer
        }
    }

    private func handleCompactClick() {
        // This handler is only the compact notch's click-to-open
        // entry point. Expanded dismissal has a separately scoped monitor.
        if !isCollapsing && model.isVisible && !model.isExpanded && targetFrame(expanded: false, page: .controls).contains(NSEvent.mouseLocation) {
            model.openManually()
        }
    }

    private func dismissExpandedPanel() {
        guard model.isExpanded else { return }
        openTimer?.invalidate()
        openTimer = nil
        closeTimer?.invalidate()
        closeTimer = nil
        panel.ignoresMouseEvents = true
        collapseUntil = ProcessInfo.processInfo.systemUptime + 0.20
        model.closeExplicitly()
    }

    private func selectScreenAndPosition() {
        let screens = NSScreen.screens
        targetScreen = screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? screens.first

        guard let screen = targetScreen else { return }

        let menuBarHeight = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        let notchHeight = screen.safeAreaInsets.top > 0
            ? screen.safeAreaInsets.top
            : menuBarHeight

        var physicalWidth: CGFloat = 185
        var notchCenterX = screen.frame.midX
        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            physicalWidth = screen.frame.width - left.width - right.width
            notchCenterX = screen.frame.minX + left.width + physicalWidth / 2
        }

        model.setPhysicalNotchSize(width: physicalWidth, height: notchHeight)
        collapsedSize = CGSize(width: physicalWidth, height: notchHeight)
        collapsedFrame = NSRect(
            x: notchCenterX - physicalWidth / 2,
            y: screen.frame.maxY - notchHeight,
            width: physicalWidth,
            height: notchHeight
        )
        handleStateChange(expanded: model.isExpanded, page: model.activePage)
    }

    private func targetFrame(expanded: Bool, page: ShelfPage) -> NSRect {
        guard let screen = targetScreen else { return .zero }
        let size: CGSize
        if expanded {
            size = CGSize(width: min(page.expandedSize.width + (model.preferences.wideLayout ? 80 : 0), screen.frame.width - 16),
                          height: min(page.expandedSize.height, screen.visibleFrame.height))
        } else {
            size = CGSize(width: HarborLayout.collapsedWidth(physicalWidth: collapsedSize.width, playing: model.showsNowPlaying), height: collapsedSize.height)
        }

        return NSRect(
            x: collapsedFrame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func scheduleStateUpdate() {
        guard !stateUpdateScheduled else { return }
        stateUpdateScheduled = true
        // @Published emits before the property is assigned. Lay out only after
        // both the model and SwiftUI can see the committed state.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isStopped else { return }
            self.stateUpdateScheduled = false
            self.handleStateChange(expanded: self.model.isExpanded, page: self.model.activePage)
        }
    }

    private func handleStateChange(expanded: Bool, page: ShelfPage) {

        let frame = targetFrame(expanded: expanded, page: page)
        guard frame != .zero else { return }
        updateCompactClickMonitors()

        if expanded && model.isVisible && !displayAsleep {
            dismissalMonitor.start(window: panel) { [weak self] in self?.dismissExpandedPanel() }
        } else {
            dismissalMonitor.stop()
        }
        frameTransition += 1
        let transition = frameTransition

        // Never leave an expanded, transparent window waiting for an animation
        // callback. Collapsed windows cannot swallow another app's clicks.
        // Input availability must not depend on an animation completion that
        // can be canceled by sleep, display changes, or a presentation switch.
        panel.ignoresMouseEvents = !expanded || !model.isVisible || displayAsleep
        let animate = model.isVisible && panel.isVisible && panel.frame != .zero
            && model.preferences.animate && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let duration: TimeInterval = animate ? (expanded ? 0.24 : 0.20) : 0
        // Bound suppression to the existing animation, without a new timer.
        // A canceled completion must never leave the compact notch unclickable.
        collapseUntil = !expanded && panel.frame != frame ? ProcessInfo.processInfo.systemUptime + duration : 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.frameTransition == transition else { return }
                self.collapseUntil = 0
            }
        }
        panel.contentView?.needsLayout = true
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.contentView?.needsDisplay = true
        if model.isVisible { panel.orderFrontRegardless() }
    }

    private func applyVisibility(_ visible: Bool) {
        if visible {
            setupMonitors()
            panel.orderFrontRegardless()
        } else {
            removeMonitors()
            closeTimer?.invalidate()
            closeTimer = nil
            panel.ignoresMouseEvents = true
            panel.orderOut(nil)
        }
    }
}

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
