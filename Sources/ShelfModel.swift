import AppKit
import Combine
import Foundation

enum ShelfPage {
    case controls
    case settings
    case about
    case music
    case mirror

    var expandedSize: CGSize {
        switch self {
        case .controls: return CGSize(width: 420, height: 380)
        case .settings: return CGSize(width: 440, height: 600)
        case .about: return CGSize(width: 440, height: 460)
        case .music: return CGSize(width: 620, height: 330)
        case .mirror: return CGSize(width: 420, height: 420)
        }
    }
}

@MainActor
final class ShelfModel: ObservableObject {
    let preferences: HarborPreferences
    @Published var isExpanded = false
    @Published var activePage: ShelfPage = .controls
    @Published var showsNowPlaying = false
    @Published var hasSpotifyTrack = false
    @Published private(set) var isVisible: Bool
    @Published private(set) var physicalNotchWidth: CGFloat = 185
    @Published private(set) var physicalNotchHeight: CGFloat = 34

    // The controller rechecks pointer position at a single exit deadline.
    private var exitedAt: TimeInterval?
    private var enteredAt: TimeInterval?
    static let hoverDelay: TimeInterval = 0.18
    var pendingOpen: Bool { enteredAt != nil && !isExpanded }
    private var requiresPointerExit = false
    private(set) var isManuallyOpened = false

    init(preferences: HarborPreferences? = nil) {
        self.preferences = preferences ?? HarborPreferences()
        isVisible = true
        UserDefaults.standard.set(true, forKey: "isShelfVisible")
    }

    func start() {
        // Shelf is active
    }

    func stop() {
        exitedAt = nil
        enteredAt = nil
    }

    func resetAfterWake() {
        close()
        requiresPointerExit = false
    }

    func toggleExpanded() {
        if isExpanded {
            close()
        } else {
            openManually()
        }
    }

    func openManually() {
        requiresPointerExit = false
        isManuallyOpened = true
        open()
    }

    func open() {
        guard isVisible else { return }
        enteredAt = nil
        exitedAt = nil
        guard !isExpanded else { return }
        isExpanded = true
        activePage = hasSpotifyTrack ? .music : .controls
    }

    func close() {
        enteredAt = nil
        isManuallyOpened = false
        exitedAt = nil
        guard isExpanded else { return }
        activePage = .controls
        isExpanded = false
    }

    func closeExplicitly() {
        close()
        requiresPointerExit = true
    }

    func setVisible(_ visible: Bool) {
        isVisible = visible
        UserDefaults.standard.set(visible, forKey: "isShelfVisible")
        if !visible {
            close()
        }
    }

    func setPhysicalNotchSize(width: CGFloat, height: CGFloat) {
        physicalNotchWidth = width
        physicalNotchHeight = height
    }

    func reportPointerState(
        inside: Bool,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        guard isVisible else { return }
        if requiresPointerExit {
            if !inside { requiresPointerExit = false }
            return
        }

        if inside {
            isManuallyOpened = false
            exitedAt = nil

            if isExpanded { return }

            guard preferences.openOnHover else { enteredAt = nil; return }
            if enteredAt == nil { enteredAt = now }
            if now - (enteredAt ?? now) >= preferences.openingDelay { open() }
        } else {
            enteredAt = nil

            if !isExpanded { return }

            // When opened explicitly via launch or Finder, don't auto-collapse
            if isManuallyOpened { return }

            if exitedAt == nil { exitedAt = now }
            if now - (exitedAt ?? now) >= preferences.closingDelay { close() }
        }
    }
}
