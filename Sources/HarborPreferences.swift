import Combine
import Foundation

@MainActor
final class HarborPreferences: ObservableObject {
    private let defaults: UserDefaults
    @Published var openOnHover: Bool { didSet { defaults.set(openOnHover, forKey: "harbor.openOnHover") } }
    @Published var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: "harbor.hoverDelay") } }
    @Published var closeDelay: Double { didSet { defaults.set(closeDelay, forKey: "harbor.closeDelay") } }
    @Published var wideLayout: Bool { didSet { defaults.set(wideLayout, forKey: "harbor.wideLayout") } }
    @Published var animate: Bool { didSet { defaults.set(animate, forKey: "harbor.animate") } }
    @Published var accent: String { didSet { defaults.set(accent, forKey: "harbor.accent") } }
    @Published var spotifyEnabled: Bool { didSet { defaults.set(spotifyEnabled, forKey: "harbor.spotify") } }
    @Published var mirrorEnabled: Bool { didSet { defaults.set(mirrorEnabled, forKey: "harbor.mirror") } }

    var openingDelay: Double { Self.bounded(hoverDelay, fallback: 0.18, range: 0...1) }
    var closingDelay: Double { Self.bounded(closeDelay, fallback: 0.28, range: 0.1...1) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        openOnHover = defaults.object(forKey: "harbor.openOnHover") as? Bool ?? true
        hoverDelay = defaults.object(forKey: "harbor.hoverDelay") as? Double ?? 0.18
        closeDelay = defaults.object(forKey: "harbor.closeDelay") as? Double ?? 0.28
        wideLayout = defaults.bool(forKey: "harbor.wideLayout")
        animate = defaults.object(forKey: "harbor.animate") as? Bool ?? true
        accent = defaults.string(forKey: "harbor.accent") ?? "Red"
        spotifyEnabled = defaults.object(forKey: "harbor.spotify") as? Bool ?? true
        mirrorEnabled = defaults.object(forKey: "harbor.mirror") as? Bool ?? true
    }

    static func bounded(_ value: Double, fallback: Double, range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
    }
}

enum HarborLayout {
    static func popupHeight(available: Double, music: Bool = false) -> Double { min(music ? 310 : 420, max(160, available - 40)) }
    static func collapsedWidth(physicalWidth: Double, playing: Bool) -> Double {
        physicalWidth + (playing ? 88 : 0)
    }
}
