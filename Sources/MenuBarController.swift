import AppKit
import Combine
import SwiftUI

@MainActor
private final class HarborSurface: ObservableObject {
    @Published var visible = false
    @Published var height: CGFloat = 420
    @Published var width: CGFloat = 420
}

private struct HostedHarborView: View {
    @ObservedObject var surface: HarborSurface
    let appDelegate: AppDelegate
    var body: some View {
        Group {
            if surface.visible {
                NotchView(model: appDelegate.shelfModel, appDelegate: appDelegate, preferences: appDelegate.preferences, isIsland: false)
            } else { Color.black }
        }.frame(width: surface.width, height: surface.height)
    }
}

/// Owns the status item independently of SwiftUI scene insertion/removal.
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate, NSWindowDelegate {
    private weak var appDelegate: AppDelegate?
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private let controlsWindow: NSWindow
    private let controlsSurface = HarborSurface()
    private let popoverSurface = HarborSurface()
    private var pageSubscription: AnyCancellable?

    init(appDelegate: AppDelegate) {
        controlsWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 640),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        self.appDelegate = appDelegate
        controlsWindow.delegate = self
        popover.delegate = self
        controlsWindow.title = "NotchHarbor Controls — \(appDelegate.version)"
        controlsWindow.isReleasedWhenClosed = false
        controlsWindow.contentViewController = NSHostingController(rootView:
            HostedHarborView(surface: controlsSurface, appDelegate: appDelegate)
        )
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: HostedHarborView(surface: popoverSurface, appDelegate: appDelegate)
        )
        popover.contentViewController?.view.setFrameSize(NSSize(width: 420, height: 420))
        pageSubscription = appDelegate.shelfModel.$activePage.removeDuplicates()
            .receive(on: RunLoop.main).sink { [weak self] page in self?.resizeForPage(page) }
    }

    func setVisible(_ visible: Bool) {
        if visible {
            if let item {
                item.isVisible = true
                return
            }
            let item = NSStatusBar.system.statusItem(withLength: 28)
            let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
                let path = NSBezierPath()
                path.move(to: NSPoint(x: 2, y: 13))
                path.line(to: NSPoint(x: 6, y: 13))
                path.line(to: NSPoint(x: 6, y: 8))
                path.curve(to: NSPoint(x: 8, y: 6), controlPoint1: NSPoint(x: 6, y: 6), controlPoint2: NSPoint(x: 7, y: 6))
                path.line(to: NSPoint(x: 12, y: 6))
                path.curve(to: NSPoint(x: 14, y: 8), controlPoint1: NSPoint(x: 13, y: 6), controlPoint2: NSPoint(x: 14, y: 6))
                path.line(to: NSPoint(x: 14, y: 13))
                path.line(to: NSPoint(x: 18, y: 13))
                path.lineWidth = 1.5
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                NSColor.black.setStroke()
                path.stroke()
                NSBezierPath(roundedRect: NSRect(x: 7, y: 2, width: 6, height: 1.5), xRadius: 0.75, yRadius: 0.75).fill()
                return true
            }
            image.isTemplate = true
            item.button?.image = image
            item.button?.setAccessibilityLabel("NotchHarbor controls")
            item.button?.toolTip = "NotchHarbor"
            item.button?.target = self
            item.button?.action = #selector(togglePopover)
            self.item = item
            item.isVisible = true
        } else {
            dismiss()
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
        }
    }

    func showControls() {
        // Finder reopen must work even when macOS hides a crowded status item.
        popover.close()
        appDelegate?.shelfModel.closeExplicitly()
        appDelegate?.shelfModel.activePage = .controls
        controlsSurface.visible = true
        controlsSurface.width = 420
        if let screen = NSScreen.main {
            controlsSurface.height = HarborLayout.popupHeight(available: screen.visibleFrame.height)
            controlsWindow.setContentSize(NSSize(width: 420, height: controlsSurface.height))
        }
        controlsWindow.center()
        NSApp.activate(ignoringOtherApps: true)
        controlsWindow.makeKeyAndOrderFront(nil)
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.close()
        } else if let button = item?.button, button.window?.isVisible == true {
            controlsSurface.visible = false
            controlsWindow.orderOut(nil)
            appDelegate?.shelfModel.activePage = .controls
            popoverSurface.visible = true
            popoverSurface.width = 420
            let available = button.window?.screen?.visibleFrame.height ?? 640
            popoverSurface.height = HarborLayout.popupHeight(available: available)
            popover.contentSize = NSSize(width: 420, height: popoverSurface.height)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        } else {
            showControls()
        }
    }

    func dismiss() {
        controlsSurface.visible = false
        popoverSurface.visible = false
        stopMedia()
        popover.close()
        controlsWindow.orderOut(nil)
    }

    private func stopMedia() {
        appDelegate?.mirror.stop()
        appDelegate?.spotify.disappear()
        appDelegate?.shelfModel.activePage = .controls
    }

    private func resizeForPage(_ page: ShelfPage) {
        if controlsSurface.visible {
            controlsSurface.width = page == .music ? 620 : 420
            controlsSurface.height = HarborLayout.popupHeight(available: Double(controlsWindow.screen?.visibleFrame.height ?? 640), music: page == .music)
            controlsWindow.setContentSize(NSSize(width: controlsSurface.width, height: controlsSurface.height))
        }
        if popoverSurface.visible {
            popoverSurface.width = page == .music ? 620 : 420
            popoverSurface.height = HarborLayout.popupHeight(available: Double(item?.button?.window?.screen?.visibleFrame.height ?? 640), music: page == .music)
            popover.contentSize = NSSize(width: popoverSurface.width, height: popoverSurface.height)
        }
    }
    func popoverDidClose(_ notification: Notification) { popoverSurface.visible = false; stopMedia() }
    func windowWillClose(_ notification: Notification) { controlsSurface.visible = false; stopMedia() }
}
