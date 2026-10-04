import AppKit
import SwiftUI

private let mechaKeysIcon: NSImage = {
    guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
          let image = NSImage(contentsOf: url) else {
        return NSApplication.shared.applicationIconImage
    }
    return image
}()

struct NotchView: View {
    @ObservedObject var model: ShelfModel
    @ObservedObject var appDelegate: AppDelegate
    @ObservedObject var preferences: HarborPreferences
    var isIsland = true

    var body: some View {
        ZStack(alignment: .top) {
            Color.black

            if isIsland && !model.isExpanded && model.showsNowPlaying {
                CollapsedSpotifyView(controller: appDelegate.spotify, physicalWidth: model.physicalNotchWidth)
            }

            if model.isExpanded || !isIsland {
                VStack(spacing: 12) {
                  Group {
                    switch model.activePage {
                    case .controls:
                        ScrollView { controlsPage }
                    case .settings:
                        Button("Open Settings…") { appDelegate.showSettings() }
                    case .about:
                        aboutPage
                    case .music:
                        if preferences.spotifyEnabled { ScrollView { SpotifyView(controller: appDelegate.spotify, library: appDelegate.spotifyLibrary) } }
                    case .mirror:
                        if preferences.mirrorEnabled { ScrollView { MirrorView(controller: appDelegate.mirror) } }
                    }
                  }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                  bottomTabs
                }
                .padding(.horizontal, 16)
                .padding(.top, isIsland ? max(14, model.physicalNotchHeight + 6) : 14)
                .padding(.bottom, 14)
                .foregroundStyle(.white)
            }
        }
        .clipShape(
            NotchShape(
                topCornerRadius: isIsland && model.isExpanded ? 10 : 0,
                bottomCornerRadius: isIsland ? (model.isExpanded ? 22 : 14) : 0
            )
        )
        // The panel owns the animated bounds, keeping drawing and hit testing aligned.
        // Frame and visibility must change atomically with the AppKit panel.
        // Animating a separate SwiftUI frame can leave transparent hit regions.
        .transaction { $0.animation = nil }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .environment(\.colorScheme, .dark)
        .tint(preferences.tint)
        .onChange(of: preferences.spotifyEnabled) { enabled in
            if !enabled && model.activePage == .music { model.activePage = .controls }
        }
        .onChange(of: preferences.mirrorEnabled) { enabled in
            if !enabled { appDelegate.mirror.stop() }
            if !enabled && model.activePage == .mirror { model.activePage = .controls }
        }
    }

    private var bottomTabs: some View {
        HStack(spacing: 12) {
            tab("Keys", symbol: "keyboard", page: .controls)
            if preferences.spotifyEnabled { tab("Music", symbol: "music.note", page: .music) }
            if preferences.mirrorEnabled { tab("Mirror", symbol: "camera", page: .mirror) }
            Spacer(minLength: 0)
            Button { appDelegate.showSettings() } label: { Image(systemName: "gearshape") }
                .help("NotchHarbor Settings")
        }.buttonStyle(.plain).font(.caption.weight(.semibold))
            .padding(.top, 10).overlay(alignment: .top) { Divider().overlay(.white.opacity(0.12)) }
    }

    private func tab(_ title: String, symbol: String, page: ShelfPage) -> some View {
        Button { model.activePage = page } label: {
            Label(title, systemImage: symbol).padding(8)
                .background(model.activePage == page ? preferences.tint.opacity(0.25) : .clear, in: Capsule())
        }.accessibilityAddTraits(model.activePage == page ? .isSelected : [])
    }

    private var controlsPage: some View {
        VStack(spacing: 11) {
            header
            primaryButton
            profileButtons
            volumeControl

            if !appDelegate.hasKeyboardAccess {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Input Monitoring access needed")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Grant") {
                        appDelegate.openKeyboardSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            actions
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard.fill")
                .font(.title3)
                .foregroundStyle(preferences.tint)

            Text("NotchHarbor")
                .font(.headline.weight(.bold))

            Spacer()

            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(appDelegate.statusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)

            Button {
                appDelegate.showSettings()
            } label: {
                Image(systemName: "gearshape.fill")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.72))
            .help("NotchHarbor Settings")
        }
    }

    private var primaryButton: some View {
        Button {
            appDelegate.toggleSounds()
        } label: {
            Label(primaryButtonTitle, systemImage: primaryButtonIcon)
                .font(.body.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(primaryButtonColor)
        .disabled(appDelegate.bluetoothAudioConnected || appDelegate.callMuteActive)
    }

    private var profileButtons: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SWITCH SOUND")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.52))

            HStack(spacing: 4) {
                profileButton("Default", profile: .standard)
                profileButton("K Pro Red", profile: .red)
                profileButton("Alpaca", profile: .alpaca)
            }
            .padding(3)
            .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))

            Menu {
                Section("Included Profiles") {
                    ForEach(KeyboardSoundProfile.communityProfiles) { profile in
                        Button {
                            appDelegate.selectSoundProfile(profile)
                        } label: {
                            if appDelegate.soundProfile == profile {
                                Label(profile.rawValue, systemImage: "checkmark")
                            } else {
                                Text(profile.rawValue)
                            }
                        }
                    }
                }
                Divider()
                ForEach(appDelegate.customSoundPacks) { pack in
                    Button {
                        appDelegate.selectCustomSoundPack(pack)
                    } label: {
                        if appDelegate.selectedCustomPackID == pack.id {
                            Label(pack.name, systemImage: "checkmark")
                        } else {
                            Text(pack.name)
                        }
                    }
                }
                if !appDelegate.customSoundPacks.isEmpty { Divider() }
                Button("Import Sound Pack…", systemImage: "plus") {
                    appDelegate.importCustomSoundPack()
                }
            } label: {
                Label(
                    appDelegate.soundProfile == .custom
                        ? appDelegate.selectedProfileName
                        : (KeyboardSoundProfile.communityProfiles.contains(appDelegate.soundProfile)
                            ? appDelegate.selectedProfileName
                            : "More Sound Profiles"),
                    systemImage: "waveform.badge.plus"
                )
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 24)
            }
            .menuStyle(.borderlessButton)
            .disabled(!appDelegate.soundEnabled)
        }
    }

    private func profileButton(_ name: String, profile: KeyboardSoundProfile) -> some View {
        let isSelected = appDelegate.soundProfile == profile
        return Button {
            appDelegate.selectSoundProfile(profile)
        } label: {
            HStack(spacing: 5) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                }
                Text(name)
                    .lineLimit(1)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSelected ? .white : .white.opacity(0.68))
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(
                isSelected ? preferences.tint : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!appDelegate.soundEnabled)
    }

    private var volumeControl: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .foregroundStyle(.white.opacity(0.62))

            VolumeLevelSlider(
                value: Binding(
                    get: { appDelegate.volume },
                    set: { appDelegate.setVolume($0) }
                ),
                isEnabled: appDelegate.soundEnabled,
                tint: preferences.tint
            )

            Text("\(Int(appDelegate.volume * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.66))
                .frame(width: 35, alignment: .trailing)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button("Play Test", systemImage: "play.fill") {
                appDelegate.playTestSound()
            }
            .buttonStyle(.bordered)
            .disabled(!appDelegate.soundEnabled)

            Spacer()

            Button("About", systemImage: "info.circle") {
                model.activePage = .about
            }
            .buttonStyle(.bordered)

            Button("Quit", systemImage: "power", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.bordered)
        }
        .font(.caption.weight(.semibold))
    }

    private var footer: some View {
        HStack {
            if let error = appDelegate.audioError {
                Label("Audio unavailable — try Play Test", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(error)
            } else if appDelegate.bluetoothAudioConnected {
                Label("Paused for BT audio", systemImage: "airpodspro")
                    .foregroundStyle(.orange)
            } else if appDelegate.callMuteActive {
                Label("Paused while microphone is active", systemImage: "mic.fill")
                    .foregroundStyle(.orange)
            } else {
                Text("NotchHarbor \(appDelegate.version)")
                    .foregroundStyle(.white.opacity(0.36))
            }

            Spacer()
        }
        .font(.caption2)
    }


    private var aboutPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    model.activePage = .controls
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)

                Spacer()
                Text("About NotchHarbor")
                    .font(.headline.weight(.bold))
                Spacer()

                Button {
                    model.closeExplicitly()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: 24, height: 20)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                Image(nsImage: mechaKeysIcon)
                    .resizable()
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("NotchHarbor \(appDelegate.version)")
                        .font(.subheadline.weight(.bold))
                    Text("Home of MechaKeys keyboard sounds")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }

            Divider().overlay(.white.opacity(0.12))

            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    featureRow(icon: "music.note", title: "Spotify Desktop controls",
                               description: "A compact player and clickable Spotify icon. Only confirmed playback on this Mac decorates the collapsed island; paused tracks remain inside Music. Optional playlists use separate Spotify sign-in with renewal access in Keychain. Playback uses events, not polling.")
                    featureRow(icon: "camera.fill", title: "Private camera mirror",
                               description: "Start a circular mirror when needed. No recording, microphone capture or uploads. Closing, tab changes and sleep stop the camera.")
                    featureRow(icon: "paintpalette.fill", title: "Make the island yours",
                               description: "A separate settings window provides accent, width, animation, click-only opening and adjustable hover/close delays.")
                    featureRow(
                        icon: "info.circle.fill",
                        title: "Community build — not notarized",
                        description: "Free community software, locally signed and not notarized by Apple. macOS may require approval before opening and Input Monitoring permission after updates. Never disable Gatekeeper to run this app."
                    )
                    featureRow(
                        icon: "arrow.down.circle",
                        title: "Optional update checks",
                        description: "Use Settings → Check for Updates, or enable daily checks. Checks contact GitHub and show public releases. Downloads and installation stay manual; daily checks are off by default."
                    )
                    featureRow(
                        icon: "bolt.fill",
                        title: "Low-latency playback",
                        description: "Preloaded 48 kHz sounds, a warm audio engine, polyphonic playback, and stale-event dropping keep sound aligned with input."
                    )
                    featureRow(
                        icon: "keyboard.fill",
                        title: "Recorded sound profiles",
                        description: "Choose Default, K Pro Red, Alpaca, Holy Panda, MX Blue, MX Brown, NK Cream, Typewriter, or a validated custom pack."
                    )
                    featureRow(
                        icon: "music.note.list",
                        title: "Privately approved recordings",
                        description: "Five included profiles are used with permission. Their recordings may not be extracted, reused, repackaged, or redistributed separately."
                    )
                    featureRow(
                        icon: "waveform.badge.plus",
                        title: "Custom sound packs",
                        description: "Import short WAV, AIFF, CAF, or MP3 recordings for keys, Space, Delete, Enter, mouse clicks, and optional key releases."
                    )
                    featureRow(
                        icon: "slider.horizontal.3",
                        title: "Natural typing dynamics",
                        description: "Optional subtle pitch variation and typing-speed dynamics add character while playback stays preloaded and polyphonic."
                    )
                    featureRow(
                        icon: "mic.slash.fill",
                        title: "Automatic microphone pause",
                        description: "Optionally pauses sounds while any microphone is active, using Core Audio events instead of continuous polling."
                    )
                    featureRow(
                        icon: "delete.left.fill",
                        title: "Special-key sounds",
                        description: "K Pro Red separates regular keys, Space, and mouse clicks. Alpaca also has distinct Delete/Backspace sounds. Default uses shared click variations."
                    )
                    featureRow(
                        icon: "hifispeaker.2.fill",
                        title: "Spatial audio",
                        description: "Left-side keys pan left and right-side keys pan right for a subtle physical-keyboard effect."
                    )
                    featureRow(
                        icon: "computermouse.fill",
                        title: "Mouse click feedback",
                        description: "Left, right, and other mouse-button presses receive profile-matched click sounds."
                    )
                    featureRow(
                        icon: "airpodspro",
                        title: "Bluetooth-aware",
                        description: "Sounds pause when a Bluetooth headset, earphone, or speaker connects and resume automatically after it disconnects."
                    )
                    featureRow(
                        icon: "leaf.fill",
                        title: "Idle-aware audio and hover",
                        description: "Audio sleeps after 30 seconds without input; wake-up never replays a backlog. Hover uses mouse events instead of continuous polling. Battery impact varies with usage."
                    )
                    featureRow(
                        icon: "display",
                        title: "Native MacBook Notch",
                        description: "Choose island or menu-bar controls in Settings. In island mode, pause over the notch briefly to open; quick passes and dragging do not open it."
                    )
                    featureRow(
                        icon: "lock.shield.fill",
                        title: "Private typing",
                        description: "Sounds work offline. No typed text or analytics are collected. Optional update checks contact GitHub; keyboard and mouse activity are never sent."
                    )
                    featureRow(
                        icon: "laptopcomputer",
                        title: "Universal Mac support",
                        description: "Runs natively on Apple Silicon and Intel Macs with macOS 13 or newer."
                    )
                }
                .padding(.trailing, 6)
            }
            .frame(maxHeight: 205)

            Divider().overlay(.white.opacity(0.12))

            Text("Built by orstsm")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func featureRow(
        icon: String,
        title: String,
        description: String
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(preferences.tint)
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.60))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var primaryButtonTitle: String {
        if appDelegate.bluetoothAudioConnected {
            return "Paused for BT Audio"
        }
        if appDelegate.callMuteActive {
            return "Paused While Microphone Is Active"
        }
        return appDelegate.soundEnabled ? "Turn Sounds Off" : "Turn Sounds On"
    }

    private var primaryButtonIcon: String {
        if appDelegate.bluetoothAudioConnected {
            return "speaker.slash.fill"
        }
        if appDelegate.callMuteActive { return "mic.slash.fill" }
        return appDelegate.soundEnabled ? "speaker.slash.fill" : "speaker.wave.2.fill"
    }

    private var primaryButtonColor: Color {
        if appDelegate.bluetoothAudioConnected {
            return .orange
        }
        if appDelegate.callMuteActive { return .orange }
        return appDelegate.soundEnabled ? .red : .green
    }

    private var statusColor: Color {
        if appDelegate.bluetoothAudioConnected { return .orange }
        if appDelegate.callMuteActive { return .orange }
        if appDelegate.audioError != nil || (appDelegate.soundEnabled && !appDelegate.hasKeyboardAccess) { return .orange }
        return appDelegate.soundEnabled ? .green : .red
    }
}

private struct VolumeLevelSlider: View {
    @Binding var value: Double
    let isEnabled: Bool
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            let thumbSize: CGFloat = 18
            let usableWidth = max(0, geometry.size.width - thumbSize)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.20))
                    .frame(height: 6)

                Capsule()
                    .fill(tint)
                    .frame(width: max(3, geometry.size.width * value), height: 6)

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.32), radius: 2, y: 1)
                    .offset(x: usableWidth * value)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard isEnabled, geometry.size.width > 0 else { return }
                        value = min(max(gesture.location.x / geometry.size.width, 0), 1)
                    }
            )
        }
        .frame(height: 20)
        .opacity(isEnabled ? 1 : 0.38)
        .accessibilityLabel("NotchHarbor volume")
        .accessibilityValue("\(Int(value * 100)) percent")
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            switch direction {
            case .increment:
                value = min(value + 0.05, 1)
            case .decrement:
                value = max(value - 0.05, 0)
            @unknown default:
                break
            }
        }
    }
}

/// Dynamic Notch shape inspired by BoringNotch:
/// Flat against the top screen bezel with outward-curving ears at the top
/// and rounded corners at the bottom.
struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    init(topCornerRadius: CGFloat = 10, bottomCornerRadius: CGFloat = 22) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Start at top-left edge flush with screen bezel
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Top-left ear curving down and inwards
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
        )

        // Left vertical edge down to bottom corner
        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius))

        // Bottom-left rounded corner
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))

        // Bottom-right rounded corner
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY)
        )

        // Right vertical edge up to top corner
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius))

        // Top-right ear curving up and outwards to screen bezel
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY)
        )

        // Top flat edge closing back to top-left
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        return path
    }
}
