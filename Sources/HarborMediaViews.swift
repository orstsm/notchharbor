import SwiftUI

struct SpotifyCover: View {
    @ObservedObject var controller: SpotifyController
    let size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: max(4, size * 0.12)).fill(.white.opacity(0.12))
            Image(systemName: "music.note").font(.system(size: size * 0.35)).foregroundStyle(.secondary)
            if let image = controller.artwork {
                Image(nsImage: image).resizable().scaledToFill()
            }
        }.frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: max(4, size * 0.12)))
    }
}

/// A playback indicator, not microphone/audio-level analysis.
struct CollapsedSpotifyView: View {
    @ObservedObject var controller: SpotifyController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let physicalWidth: CGFloat
    var body: some View {
        HStack(spacing: 0) {
            SpotifyCover(controller: controller, size: 22).frame(width: 44)
            Color.clear.frame(width: physicalWidth)
            TimelineView(.animation(minimumInterval: 0.2, paused: reduceMotion || controller.snapshot?.playing != true)) { context in
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<4) { index in
                        Capsule().fill(.pink)
                            .frame(width: 3, height: reduceMotion ? CGFloat(8 + index * 2) :
                                CGFloat(6 + 10 * abs(sin(context.date.timeIntervalSinceReferenceDate * 3 + Double(index) * 1.7))))
                    }
                }.frame(width: 44, height: 22)
            }
        }.frame(maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Spotify playing on this Mac: \(controller.snapshot?.title ?? "Music"). Hover or click to open music controls.")
    }
}

struct SpotifyView: View {
    @ObservedObject var controller: SpotifyController
    @ObservedObject var library: SpotifyLibrary
    @State private var seeking = false
    @State private var seekPosition = 0.0
    @State private var changingVolume = false
    @State private var soundVolume = 50.0
    @State private var showingVolume = false

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
          VStack(alignment: .leading, spacing: 6) {
            if let track = controller.snapshot {
                    VStack(alignment: .leading, spacing: 12) {
                      HStack(spacing: 12) {
                        SpotifyCover(controller: controller, size: 66)
                        VStack(alignment: .leading, spacing: 3) {
                          HStack(alignment: .center, spacing: 8) {
                            Text(track.title.isEmpty ? "Choose a song in Spotify" : track.title)
                                .font(.headline).lineLimit(2).help(track.title).frame(maxWidth: .infinity, alignment: .leading)
                            SpotifyLaunchButton(controller: controller)
                          }
                            Text(track.artist).font(.callout).foregroundStyle(.pink).lineLimit(1)
                            Text(controller.playbackDescription).font(.caption2).foregroundStyle(.secondary)
                        }
                      }
                        TimelineView(.animation(minimumInterval: 1, paused: !track.playing)) { context in
                            VStack(spacing: 3) {
                                Slider(value: Binding(get: { seeking ? seekPosition : track.elapsed(since: controller.sampledAt, now: context.date) },
                                                      set: { seekPosition = $0 }), in: 0...max(1, track.duration), onEditingChanged: { editing in
                                    seeking = editing
                                    if !editing { controller.send(.seek(seekPosition)) }
                                }).tint(.white).controlSize(.mini)
                                    .disabled(track.duration <= 0)
                                    .accessibilityLabel("Spotify playback position")
                                HStack {
                                    Text(Self.time(track.elapsed(since: controller.sampledAt, now: context.date)))
                                    Spacer()
                                    Text(Self.time(track.duration))
                                }.font(.caption2.monospacedDigit()).foregroundStyle(.pink)
                            }
                        }
                        HStack(spacing: 18) {
                            Button { showingVolume.toggle() } label: {
                                Image(systemName: "speaker.wave.2.fill")
                            }.help("Spotify volume").accessibilityLabel("Show Spotify volume")
                            Button { controller.send(.previous) } label: {
                                Image(systemName: "backward.fill")
                            }.accessibilityLabel("Previous track")
                            Button { controller.togglePlayback() } label: {
                                Image(systemName: track.playing ? "pause.fill" : "play.fill").font(.title2)
                                    .frame(width: 30, height: 30).contentShape(Rectangle())
                            }.accessibilityLabel(track.playing ? "Pause Spotify" : "Play Spotify")
                            Button { controller.send(.next) } label: {
                                Image(systemName: "forward.fill")
                            }.accessibilityLabel("Next track")
                            Spacer(minLength: 0)
                            Menu {
                                Button(track.shuffle ? "Turn Shuffle Off" : "Turn Shuffle On") { controller.send(.shuffle) }
                                    .disabled(!track.canShuffle)
                                Button(track.repeating ? "Turn Repeat Off" : "Turn Repeat On") { controller.send(.repeatTrack) }
                                    .disabled(!track.canRepeat)
                                Divider()
                                Button("Refresh") { controller.refresh() }.disabled(controller.busy)
                                Button("Open Spotify") { controller.openSpotify() }
                            } label: { Image(systemName: "ellipsis") }
                                .menuStyle(.borderlessButton).fixedSize().help("More Spotify controls")
                        }.buttonStyle(.plain).foregroundStyle(.white)
                        if showingVolume {
                            Slider(value: Binding(get: { changingVolume ? soundVolume : track.volume },
                                                  set: { soundVolume = $0 }), in: 0...100, onEditingChanged: { editing in
                                changingVolume = editing
                                if !editing { controller.send(.volume(soundVolume)) }
                            }).controlSize(.mini).tint(.white)
                                .accessibilityLabel("Spotify volume")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                if !controller.message.isEmpty {
                    HStack {
                        Text(controller.message).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                        Button("Retry") { controller.connect() }.font(.caption)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Label("Spotify", systemImage: "music.note").font(.headline)
                    Text(controller.message).font(.callout).multilineTextAlignment(.center)
                    HStack {
                        Button(controller.busy ? "Connecting…" : "Connect Spotify") { controller.connect() }
                            .buttonStyle(.borderedProminent).tint(.green).disabled(controller.busy)
                        Button("Open Spotify") { controller.openSpotify() }
                    }
                    Text("Connect once to enable now playing in the island.")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 12)
            }
          }.frame(maxWidth: .infinity, alignment: .topLeading)
          Divider()
          SpotifyPlaylistPane(library: library, controller: controller).frame(maxWidth: .infinity, alignment: .topLeading)
        }.padding(.vertical, 6)
        .onAppear { controller.appear() }
        .onDisappear { controller.disappear() }
    }

    private static func time(_ seconds: Double) -> String {
        let value = seconds.isFinite ? Int(min(86400, max(0, seconds))) : 0
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

private struct SpotifyLaunchButton: View {
    let controller: SpotifyController
    private static let icon: NSImage? = {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") else { return nil }
        return NSWorkspace.shared.icon(forFile: app.path)
    }()
    var body: some View {
        Button { controller.openSpotify() } label: {
            if let icon = Self.icon { Image(nsImage: icon).resizable().scaledToFit().frame(width: 24, height: 24) }
            else { Text("Spotify").font(.caption) }
        }.buttonStyle(.plain).help("Open Spotify").accessibilityLabel("Open Spotify")
    }
}

private struct SpotifyPlaylistPane: View {
    @ObservedObject var library: SpotifyLibrary
    let controller: SpotifyController
    @State private var showSetup = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your playlists").font(.headline)
                Spacer()
                if library.busy { ProgressView().controlSize(.small) }
                Button { library.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(!library.connected || library.busy).help("Refresh playlists")
                Button { showSetup.toggle() } label: { Image(systemName: "gearshape") }.help("Spotify library setup")
            }.buttonStyle(.plain)
            if !library.connected || library.needsCredentialAccess || showSetup {
                SpotifyLibrarySetup(library: library)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(library.playlists) { playlist in
                            Button { controller.playPlaylist(playlist.id) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "music.note.list").foregroundStyle(.green)
                                    Text(playlist.name).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "play.fill").font(.caption2)
                                }.padding(8).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain).help("Play \(playlist.name) in Spotify")
                        }
                        if library.hasMore {
                            Button("Load more playlists") { library.loadMore() }.disabled(library.busy)
                                .onAppear { library.loadMore() }
                        }
                    }
                }.frame(height: 140)
                if !library.message.isEmpty { Text(library.message).font(.caption2).foregroundStyle(.secondary) }
            }
        }.onAppear { library.appear() }
    }
}

struct SpotifyLibrarySetup: View {
    @ObservedObject var library: SpotifyLibrary
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !library.connected {
                TextField("Spotify app Client ID", text: $library.clientID).textFieldStyle(.roundedBorder).font(.caption)
                    .disabled(library.busy)
                Text("Add this redirect URI in your Spotify developer app:").font(.caption2).foregroundStyle(.secondary)
                Text(SpotifyLibrarySecurity.redirect).font(.caption2.monospaced()).textSelection(.enabled)
                HStack {
                    Button(library.authorizing ? "Signing in…" : "Connect Library") { library.connect() }.disabled(library.busy)
                    if library.busy { Button("Cancel") { library.cancel() } }
                }.font(.caption)
                Button("Sign in without Keychain") { library.connect(saveInKeychain: false) }.disabled(library.busy).font(.caption)
            } else {
                if library.needsCredentialAccess {
                    Button("Unlock Saved Playlists") { library.authorizeSavedAccess() }.disabled(library.busy)
                    Button("Sign in without Keychain") { library.connect(saveInKeychain: false) }.disabled(library.busy)
                    Text("Opening the app never requests a Keychain password. Unlock is optional; session-only sign-in lasts until you quit.").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("Library available for this session.").font(.caption)
                }
                if library.hasUnsavedAccess {
                    Button("Save Access in Keychain…") { library.rememberAccess() }.disabled(library.busy).font(.caption)
                    Text("Renewed access is in memory only. Save it if you want to unlock it after restarting; saving may ask for your Mac password.").font(.caption2).foregroundStyle(.secondary)
                }
                Button("Disconnect Library") { library.disconnect() }.disabled(library.busy).font(.caption)
            }
            if !library.message.isEmpty { Text(library.message).font(.caption2).foregroundStyle(.secondary).lineLimit(4) }
            Link("Spotify developer setup ↗", destination: URL(string: "https://developer.spotify.com/dashboard")!).font(.caption2)
            Text("Developer-app owner needs Spotify Premium. Never enter a client secret.").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct MirrorView: View {
    @ObservedObject var controller: MirrorController
    var body: some View {
        VStack(spacing: 12) {
            Text("Quick mirror").font(.headline)
            ZStack {
                Circle().fill(.white.opacity(0.08))
                if controller.running {
                    MirrorPreview(session: controller.session).clipShape(Circle())
                } else {
                    Image(systemName: "camera.fill").font(.system(size: 36)).foregroundStyle(.secondary)
                }
            }.frame(width: 180, height: 180)
                .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
            Text(controller.message).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button(controller.running ? "Stop Camera" : (controller.starting ? "Starting…" : "Start Mirror")) {
                if controller.running { controller.stop() } else { controller.start() }
            }.buttonStyle(.bordered).disabled(controller.starting)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear { controller.stop() }
    }
}
