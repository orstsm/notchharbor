import AppKit
import SwiftUI

extension HarborPreferences {
    var tint: Color {
        switch accent {
        case "Blue": return .blue
        case "Purple": return .purple
        case "Green": return .green
        default: return .red
        }
    }
}

@MainActor
final class HarborSettingsController {
    private let window: NSWindow
    init(appDelegate: AppDelegate) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "NotchHarbor Settings"
        window.minSize = NSSize(width: 640, height: 440)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: HarborSettingsView(appDelegate: appDelegate, preferences: appDelegate.preferences))
    }
    func show() {
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General", appearance = "Appearance", behavior = "Notch Behavior", sounds = "Keyboard Sounds", media = "Music & Mirror", updates = "Updates"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintpalette"
        case .behavior: return "cursorarrow.motionlines"
        case .sounds: return "keyboard"
        case .media: return "music.note"
        case .updates: return "arrow.down.circle"
        }
    }
}

struct HarborSettingsView: View {
    @ObservedObject var appDelegate: AppDelegate
    @ObservedObject var preferences: HarborPreferences
    @State private var selected: SettingsSection = .general
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("NotchHarbor").font(.title3.weight(.bold)).padding(.bottom, 14)
                ForEach(SettingsSection.allCases) { section in
                    Button { selected = section } label: {
                        Label(section.rawValue, systemImage: section.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                            .background(selected == section ? preferences.tint.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Text("Version \(appDelegate.version)").font(.caption).foregroundStyle(.secondary)
            }.padding(16).frame(width: 190).background(.quaternary.opacity(0.4))
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                Text(selected.rawValue).font(.title2.weight(.bold))
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) { content }
                        .padding(.trailing, 8).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.tint(preferences.tint).toggleStyle(.switch)
    }

    @ViewBuilder private var content: some View {
        switch selected {
        case .general:
            Toggle("Launch at Login", isOn: Binding(get: { appDelegate.launchAtLogin }, set: appDelegate.setLaunchAtLogin))
            Toggle("Use Menu Bar Instead of Island", isOn: Binding(get: { appDelegate.showsMenuBarIcon }, set: appDelegate.setShowsMenuBarIcon))
            Text("On: controls open beneath the menu-bar icon. Off: use the island at the top of your screen. Reopening NotchHarbor from Applications always opens a controls window.").font(.callout).foregroundStyle(.secondary)
            Divider()
            Text(appDelegate.hasKeyboardAccess ? "Input Monitoring is enabled." : "Input Monitoring access is needed for keyboard sounds.")
            Button("Input Monitoring Settings…") { appDelegate.openKeyboardSettings() }
        case .appearance:
            Toggle("Wider expanded island", isOn: $preferences.wideLayout)
            Picker("Accent color", selection: $preferences.accent) {
                ForEach(["Red", "Blue", "Purple", "Green"], id: \.self) { Text($0).tag($0) }
            }
            Toggle("Animate opening and closing", isOn: $preferences.animate)
            Text("The collapsed island matches the physical notch. System Reduce Motion is always respected.").font(.callout).foregroundStyle(.secondary)
        case .behavior:
            Toggle("Open island on hover", isOn: $preferences.openOnHover)
            Text("When disabled, click the island to open it. Quick passes and dragging do not trigger hover opening.").font(.callout).foregroundStyle(.secondary)
            Text("Hover delay: \(preferences.openingDelay, specifier: "%.2f") seconds")
            Slider(value: $preferences.hoverDelay, in: 0...1, step: 0.02).disabled(!preferences.openOnHover)
                .accessibilityLabel("Hover delay")
            Text("Close delay: \(preferences.closingDelay, specifier: "%.2f") seconds")
            Slider(value: $preferences.closeDelay, in: 0.1...1, step: 0.02).accessibilityLabel("Close delay")
            Button("Restore recommended timing") { preferences.hoverDelay = 0.18; preferences.closeDelay = 0.28 }
        case .sounds:
            Toggle("Mute while microphone is active", isOn: $appDelegate.muteDuringCalls)
            Toggle("Subtle pitch variation", isOn: $appDelegate.pitchVariationEnabled)
            Toggle("Typing-speed dynamics", isOn: $appDelegate.typingDynamicsEnabled)
            Toggle("Suppress held-key repeats", isOn: $appDelegate.suppressKeyRepeat)
            Toggle("Press-and-release sounds", isOn: $appDelegate.releaseSoundsEnabled)
            Button("Import Custom Sound Pack…") { appDelegate.importCustomSoundPack() }
            Text("Keyboard sounds retain preloaded playback, stale-event protection and 30-second idle suspension.").font(.caption).foregroundStyle(.secondary)
        case .media:
            Toggle("Show Spotify tab", isOn: $preferences.spotifyEnabled)
            Text("Desktop controls use playback events, not polling. The collapsed island shows artwork only while Spotify is playing on this Mac. Paused or remote playback stays hidden until you hover; Music retains the song. Playlist browsing uses a separate sign-in, with renewal access saved in Keychain.").font(.callout).foregroundStyle(.secondary)
            SpotifyLibrarySetup(library: appDelegate.spotifyLibrary)
            Divider()
            Toggle("Show camera mirror tab", isOn: $preferences.mirrorEnabled)
            Text("Camera starts only when you click Start Mirror. It stops on tab changes, closing the panel, sleep or session lock. No microphone, recording or uploads. You must start it again after waking.").font(.callout).foregroundStyle(.secondary)
        case .updates:
            UpdateSettingsView(checker: appDelegate.updateChecker)
            Text("Community build, not notarized by Apple. Downloads and installation remain manual.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
