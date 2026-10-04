import AppKit
import Combine

struct SpotifySnapshot: Decodable {
    var title: String
    var artist: String
    var album: String
    var artwork: String
    var playing: Bool
    var duration: Double
    var position: Double
    var volume: Double
    var shuffle: Bool
    var repeating: Bool
    var canShuffle: Bool
    var canRepeat: Bool

    func elapsed(since date: Date, now: Date = Date()) -> Double {
        let value = position + (playing ? max(0, now.timeIntervalSince(date)) : 0)
        return value.isFinite ? min(max(0, value), max(0, duration)) : 0
    }
}

enum SpotifyObservationPolicy {
    static func shouldObserve(connected: Bool, panelVisible: Bool, islandEnabled: Bool, suspended: Bool) -> Bool {
        connected && !suspended && (panelVisible || islandEnabled)
    }
}

/// Fixed, local Spotify commands. Track metadata is never inserted into scripts.
enum SpotifyCommand: Equatable {
    case refresh, setPlaying(Bool), next, previous, seek(Double), volume(Double), shuffle, repeatTrack, playlist(String)
    var isRefresh: Bool { self == .refresh }
    var script: String {
        switch self {
        case .refresh: return ""
        case .setPlaying(let playing): return playing ? "s.play();" : "s.pause();"
        case .playlist(let id):
            guard SpotifyPlaylistID.isValid(id) else { return "" }
            return "s.playTrack('spotify:playlist:\(id)');"
        case .next: return "s.nextTrack();"
        case .previous: return "s.previousTrack();"
        case .seek(let value): return "s.playerPosition = \(Self.safe(value, maximum: 86400));"
        case .volume(let value): return "s.soundVolume = \(Int(Self.safe(value, maximum: 100)));"
        case .shuffle: return "if (s.shufflingEnabled()) s.shuffling = !s.shuffling();"
        case .repeatTrack: return "if (s.repeatingEnabled()) s.repeating = !s.repeating();"
        }
    }
    private static func safe(_ value: Double, maximum: Double) -> Double {
        value.isFinite ? min(max(0, value), maximum) : 0
    }
}

enum SpotifyPlaylistID {
    static func isValid(_ value: String) -> Bool {
        value.count == 22 && value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }
    }
}

/// Commands take priority over coalesced refreshes. Explicit play/pause states
/// make rapid clicks deterministic instead of queuing ambiguous toggles.
struct SpotifyRequestQueue {
    private(set) var commands: [SpotifyCommand] = []
    private var needsRefresh = false
    mutating func enqueue(_ command: SpotifyCommand) {
        if command.isRefresh { needsRefresh = true; return }
        if case .setPlaying = command, let last = commands.last, case .setPlaying = last { commands.removeLast() }
        if commands.count < 32 { commands.append(command) }
    }
    mutating func next() -> SpotifyCommand? {
        if !commands.isEmpty { return commands.removeFirst() }
        if needsRefresh { needsRefresh = false; return .refresh }
        return nil
    }
}

@MainActor
final class SpotifyController: ObservableObject {
    @Published private(set) var snapshot: SpotifySnapshot?
    @Published private(set) var sampledAt = Date()
    @Published private(set) var message = "Connect to Spotify Desktop to see what’s playing."
    @Published private(set) var busy = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var localOutput: SpotifyLocalOutputState = .unavailable
    private var outputMonitor: SpotifyLocalOutputMonitor?
    var playbackDescription: String {
        guard snapshot?.playing == true else { return "Paused" }
        switch localOutput {
        case .active: return "Playing on this Mac"
        case .inactive: return "Not playing on this Mac"
        case .unavailable: return "Playback location unconfirmed"
        }
    }
    private var artworkURL: String?
    private var artworkTask: Task<Void, Never>?
    private var connected = UserDefaults.standard.bool(forKey: "harbor.spotifyConnected")
    private var visible = false
    private var islandEnabled = false
    private var suspended = false
    private var observing: Bool {
        SpotifyObservationPolicy.shouldObserve(connected: connected, panelVisible: visible, islandEnabled: islandEnabled, suspended: suspended)
    }
    private var generation = 0
    private var observationGeneration = 0
    private var requests = SpotifyRequestQueue()
    private var activeCommand: SpotifyCommand?
    private var confirmedSnapshot: SpotifySnapshot?
    private var confirmedAt = Date()
    private var observer: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var process: Process?

    func appear() {
        let alreadyObserving = observer != nil
        visible = true
        updateObservation()
        if alreadyObserving && observing { refresh() }
    }

    func setIslandMonitoring(_ enabled: Bool) {
        guard islandEnabled != enabled else { return }
        islandEnabled = enabled
        updateObservation()
    }

    func setSuspended(_ value: Bool) {
        suspended = value
        updateObservation()
    }

    private func updateObservation() {
        guard observing else { stopObservation(); return }
        guard observer == nil else { return }
        let monitorGeneration = observationGeneration
        let monitor = SpotifyLocalOutputMonitor { [weak self] state in
            Task { @MainActor in
                guard let self, self.observing, self.observationGeneration == monitorGeneration else { return }
                self.localOutput = state
            }
        }
        outputMonitor = monitor
        monitor.start()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.connected else { return }
                self.refresh()
            }
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == "com.spotify.client" else { return }
                Task { @MainActor in if self?.connected == true { self?.refresh() } }
            })
        }
        refresh()
    }

    func connect() {
        let alreadyObserving = observer != nil
        connected = true
        updateObservation()
        if alreadyObserving { refresh() }
    }

    func disappear() {
        visible = false
        updateObservation()
    }

    func stop() {
        visible = false
        islandEnabled = false
        suspended = true
        stopObservation()
    }

    private func stopObservation() {
        generation += 1
        observationGeneration += 1
        outputMonitor?.stop()
        outputMonitor = nil
        localOutput = .unavailable
        requests = SpotifyRequestQueue()
        activeCommand = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
        busy = false
        artworkTask?.cancel()
        artworkTask = nil
        if artwork == nil { artworkURL = nil }
        // Keep the last track/cover in memory across tab switches and sleep.
        // Freeze the local clock until the next confirmed state arrives.
        freezeSnapshot()
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        for token in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        workspaceObservers.removeAll()
    }

    func openSpotify() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") else {
            message = "Install Spotify Desktop, then open it and sign in."
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    func refresh() { send(.refresh) }

    func togglePlayback() {
        guard let track = snapshot else { return }
        send(.setPlaying(!track.playing))
    }

    func playPlaylist(_ id: String) {
        guard SpotifyPlaylistID.isValid(id) else { return }
        if !connected { connect() }
        send(.playlist(id))
    }

    private func freezeSnapshot() {
        guard var track = snapshot else { return }
        track.position = track.elapsed(since: sampledAt)
        track.playing = false
        sampledAt = Date()
        snapshot = track
    }

    func acceptSnapshot(_ result: SpotifySnapshot?) {
        guard var result, !result.title.isEmpty else { freezeSnapshot(); return }
        if result.artwork.isEmpty, let old = snapshot, old.title == result.title, old.artist == result.artist {
            result.artwork = old.artwork
        }
        confirmedSnapshot = result
        confirmedAt = Date()
        snapshot = result
        sampledAt = confirmedAt
        loadArtwork(result.artwork)
    }

    func send(_ command: SpotifyCommand) {
        guard observing else { return }
        outputMonitor?.refresh()
        if case .playlist(let id) = command, !SpotifyPlaylistID.isValid(id) { return }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty else {
            freezeSnapshot()
            message = "Open Spotify Desktop and choose a song."
            return
        }
        if case .setPlaying(let playing) = command, var track = snapshot {
            track.position = track.elapsed(since: sampledAt)
            track.playing = playing
            sampledAt = Date()
            snapshot = track
        }
        requests.enqueue(command)
        // Read-only metadata work can be canceled safely; never cancel or replay
        // an in-flight mutating command because it may already have executed.
        if !command.isRefresh, activeCommand?.isRefresh == true {
            generation += 1
            if let process, process.isRunning { process.terminate() }
            process = nil
            activeCommand = nil
            busy = false
        }
        drainRequests()
    }

    private func drainRequests() {
        guard observing, !busy, let command = requests.next() else { return }
        busy = true
        activeCommand = command
        if snapshot == nil { message = "Connecting… Approve Spotify control if macOS asks." }
        let token = generation
        // Run scripting off the UI and audio queues; a bounded process prevents
        // a stalled Spotify/permission dialog from freezing the island.
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        let metadataScript = """
        var s = Application('com.spotify.client');
        if (!s.running()) throw Error('Spotify is not running');
        \(command.script)
        function read(f, fallback) { try { return f(); } catch(e) { return fallback; } }
        function text(f) { return String(read(f, '')).slice(0, 2048); }
        var t = s.currentTrack;
        JSON.stringify({title:text(function(){return t.name();}), artist:text(function(){return t.artist();}),
          album:text(function(){return t.album();}), artwork:text(function(){return t.artworkUrl();}),
          playing:s.playerState() === 'playing', duration:read(function(){return t.duration()/1000;},0),
          position:read(function(){return s.playerPosition();},0), volume:read(function(){return s.soundVolume();},50),
          shuffle:read(function(){return s.shuffling();},false), repeating:read(function(){return s.repeating();},false),
          canShuffle:read(function(){return s.shufflingEnabled();},false), canRepeat:read(function(){return s.repeatingEnabled();},false)});
        """
        // A click sends only its command, without a dozen metadata round trips.
        let script = command.isRefresh ? metadataScript : "var s = Application('com.spotify.client'); if (!s.running()) throw Error('Not running'); \(command.script) JSON.stringify({ok:true});"
        child.arguments = ["-l", "JavaScript", "-e", script]
        let pipe = Pipe()
        child.standardOutput = pipe
        child.standardError = FileHandle.nullDevice
        process = child
        do { try child.run() } catch {
            process = nil
            busy = false
            activeCommand = nil
            requests = SpotifyRequestQueue()
            snapshot = confirmedSnapshot ?? snapshot
            sampledAt = confirmedAt
            freezeSnapshot()
            message = "Could not connect to Spotify. Try Connect again."
            return
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20) { if child.isRunning { child.terminate() } }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            child.waitUntilExit()
            let succeeded = data.count <= 32_768 && child.terminationStatus == 0
            let result = succeeded
                ? try? JSONDecoder().decode(SpotifySnapshot.self, from: data) : nil
            Task { @MainActor in
                guard let self, self.observing, self.generation == token else { return }
                self.busy = false
                self.process = nil
                self.activeCommand = nil
                if !succeeded || (command.isRefresh && result == nil) {
                    // Transient scripting failures are not a logout. Retain the
                    // cover and roll optimistic playback back to confirmed state.
                    self.snapshot = self.confirmedSnapshot ?? self.snapshot
                    self.sampledAt = self.confirmedAt
                    self.freezeSnapshot()
                    self.requests = SpotifyRequestQueue()
                    self.message = "Spotify did not respond. Retry, or check Spotify access in macOS Automation settings."
                } else {
                    UserDefaults.standard.set(true, forKey: "harbor.spotifyConnected")
                    self.message = ""
                    if command.isRefresh { self.acceptSnapshot(result) }
                    if !command.isRefresh { self.requests.enqueue(.refresh) }
                }
                self.outputMonitor?.refresh()
                self.drainRequests()
            }
        }
    }

    private func loadArtwork(_ value: String?) {
        guard value != artworkURL else { return }
        artworkTask?.cancel()
        artworkURL = value
        artwork = nil
        guard let value, let url = SpotifyArtwork.safeURL(value) else { return }
        artworkTask = Task { [weak self] in
            let image = await SpotifyArtwork.load(url)
            guard !Task.isCancelled, let self, self.observing, self.artworkURL == value else { return }
            self.artwork = image
        }
    }
}
