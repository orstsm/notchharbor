import AppKit
import CoreGraphics
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let preferences = HarborPreferences()
    let spotify = SpotifyController()
    let spotifyLibrary = SpotifyLibrary()
    let mirror = MirrorController()
    lazy var shelfModel = ShelfModel(preferences: preferences)
    private var settingsController: HarborSettingsController?
    private var mediaSleepObserver: NSObjectProtocol?
    private var mediaWakeObserver: NSObjectProtocol?
    private var mediaSubscriptions = Set<AnyCancellable>()
    let updateChecker = UpdateChecker(currentVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0")
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development" }
    @Published private(set) var soundEnabled: Bool
    @Published private(set) var bluetoothAudioConnected = false
    @Published private(set) var microphoneActive = false
    @Published private(set) var customSoundPacks: [CustomSoundPack]
    @Published private(set) var selectedCustomPackID: String?
    @Published var volume: Double {
        didSet {
            let validated = Self.validVolume(volume)
            if volume != validated { volume = validated }
            audioController?.setVolume(Float(volume))
            UserDefaults.standard.set(volume, forKey: "volume")
        }
    }
    @Published var soundProfile: KeyboardSoundProfile {
        didSet {
            audioController?.setProfile(soundProfile)
            UserDefaults.standard.set(soundProfile.rawValue, forKey: "soundProfile")
        }
    }
    @Published var pitchVariationEnabled: Bool {
        didSet {
            audioController?.setPitchVariationEnabled(pitchVariationEnabled)
            UserDefaults.standard.set(pitchVariationEnabled, forKey: "pitchVariationEnabled")
        }
    }
    @Published var typingDynamicsEnabled: Bool {
        didSet {
            audioController?.setTypingDynamicsEnabled(typingDynamicsEnabled)
            UserDefaults.standard.set(typingDynamicsEnabled, forKey: "typingDynamicsEnabled")
        }
    }
    @Published var suppressKeyRepeat: Bool {
        didSet {
            keyboardMonitor?.suppressKeyRepeat = suppressKeyRepeat
            UserDefaults.standard.set(suppressKeyRepeat, forKey: "suppressKeyRepeat")
        }
    }
    @Published var releaseSoundsEnabled: Bool {
        didSet {
            audioController?.setReleaseSoundsEnabled(releaseSoundsEnabled)
            UserDefaults.standard.set(releaseSoundsEnabled, forKey: "releaseSoundsEnabled")
        }
    }
    @Published var muteDuringCalls: Bool {
        didSet {
            UserDefaults.standard.set(muteDuringCalls, forKey: "muteDuringCalls")
            configureMicrophoneMonitoring()
        }
    }
    @Published private(set) var hasKeyboardAccess = false
    @Published private(set) var audioError: String?
    @Published private(set) var launchAtLogin = false
    @Published var showsMenuBarIcon: Bool {
        didSet {
            UserDefaults.standard.set(showsMenuBarIcon, forKey: "showsMenuBarIcon")
            // Do not tear down the control's owning window during its click callback.
            DispatchQueue.main.async { [weak self] in self?.applyPresentationMode() }
        }
    }

    var statusText: String {
        if bluetoothAudioConnected { return "BT paused" }
        if callMuteActive { return "Mic paused" }
        if audioError != nil { return "Audio unavailable" }
        if soundEnabled && !hasKeyboardAccess { return "Input unavailable" }
        return soundEnabled ? "Sounds on" : "Sounds off"
    }

    private var keyboardMonitor: GlobalKeyboardMonitor?
    private var accessCheckTimer: Timer?
    private var audioController: InputAudioController?
    private var bluetoothAudioMonitor: BluetoothAudioMonitor?
    private var microphoneActivityMonitor: MicrophoneActivityMonitor?
    private let customSoundPackLibrary: CustomSoundPackLibrary?
    private var userSoundEnabled: Bool

    private var notchWindowController: NotchWindowController?
    private var menuBarController: MenuBarController?
    private var lifecycleMonitor: WorkspaceLifecycleMonitor?
    private var systemSleeping = false

    var callMuteActive: Bool { muteDuringCalls && microphoneActive }

    var selectedProfileName: String {
        if soundProfile == .custom,
           let id = selectedCustomPackID,
           let pack = customSoundPacks.first(where: { $0.id == id }) {
            return pack.name
        }
        return soundProfile.rawValue
    }

    override init() {
        let defaults = UserDefaults.standard
        let library = try? CustomSoundPackLibrary()
        let restoredCustomPacks = library?.availablePacks() ?? []
        let restoredCustomPackID = defaults.string(forKey: "selectedCustomPackID")
        customSoundPackLibrary = library
        customSoundPacks = restoredCustomPacks
        selectedCustomPackID = restoredCustomPackID
        let savedSoundEnabled = defaults.object(forKey: "soundEnabled") == nil
            ? true
            : defaults.bool(forKey: "soundEnabled")
        userSoundEnabled = savedSoundEnabled
        soundEnabled = savedSoundEnabled
        volume = Self.validVolume(defaults.object(forKey: "volume") as? Double ?? 0.72)
        let savedProfile = defaults.string(forKey: "soundProfile") ?? ""
        let restoredProfile = savedProfile == "K Pro Brown"
            ? .alpaca
            : (KeyboardSoundProfile(rawValue: savedProfile) ?? .standard)
        if restoredProfile == .custom,
           let restoredCustomPackID,
           restoredCustomPacks.contains(where: { $0.id == restoredCustomPackID }) {
            soundProfile = .custom
        } else {
            soundProfile = restoredProfile == .custom ? .standard : restoredProfile
            if restoredProfile == .custom { selectedCustomPackID = nil }
        }
        pitchVariationEnabled = Self.savedBool(defaults, key: "pitchVariationEnabled", defaultValue: true)
        typingDynamicsEnabled = Self.savedBool(defaults, key: "typingDynamicsEnabled", defaultValue: true)
        suppressKeyRepeat = Self.savedBool(defaults, key: "suppressKeyRepeat", defaultValue: true)
        releaseSoundsEnabled = defaults.bool(forKey: "releaseSoundsEnabled")
        muteDuringCalls = Self.savedBool(defaults, key: "muteDuringCalls", defaultValue: true)
        if savedProfile == "K Pro Brown" {
            defaults.set(KeyboardSoundProfile.alpaca.rawValue, forKey: "soundProfile")
        }
        showsMenuBarIcon = defaults.bool(forKey: "showsMenuBarIcon")
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Publishers.CombineLatest(spotify.$snapshot, spotify.$localOutput).sink { [weak self] snapshot, output in
            guard let self else { return }
            self.shelfModel.hasSpotifyTrack = self.preferences.spotifyEnabled && snapshot != nil
            self.shelfModel.showsNowPlaying = SpotifyIslandPolicy.shouldShow(enabled: self.preferences.spotifyEnabled, playing: snapshot?.playing == true, localOutput: output)
        }.store(in: &mediaSubscriptions)
        preferences.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.updateIslandMusic() }
        }.store(in: &mediaSubscriptions)
        mediaSleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.mirror.stop()
                self?.spotify.setSuspended(true)
                self?.spotifyLibrary.cancel()
                self?.shelfModel.close()
                self?.menuBarController?.dismiss()
            }
        }
        mediaWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.systemSleeping else { return }
                self.spotify.setSuspended(false)
            }
        }
        updateChecker.start()
        LaunchAtLoginManager.hardenExistingRegistration()
        refreshLaunchAtLoginStatus()

        let bluetoothMonitor = BluetoothAudioMonitor { [weak self] isConnected in
            Task { @MainActor in
                self?.handleAudioTopologyChange(bluetoothAudioConnected: isConnected)
            }
        }
        bluetoothAudioMonitor = bluetoothMonitor
        bluetoothAudioConnected = bluetoothMonitor.hasConnectedBluetoothAudioOutput
        let microphoneMonitor = MicrophoneActivityMonitor { [weak self] isActive in
            Task { @MainActor in self?.handleMicrophoneActivityChange(isActive) }
        }
        microphoneActivityMonitor = microphoneMonitor
        microphoneActive = muteDuringCalls && microphoneMonitor.isMicrophoneActive
        soundEnabled = PlaybackPolicy.shouldEnable(
            userEnabled: userSoundEnabled,
            bluetoothAudioConnected: bluetoothAudioConnected,
            muteDuringCalls: muteDuringCalls,
            microphoneActive: microphoneActive
        )

        do {
            let controller = try InputAudioController(
                volume: Float(volume),
                profile: soundProfile,
                idleTimeout: 30
            )
            audioController = controller
            controller.setPitchVariationEnabled(pitchVariationEnabled)
            controller.setTypingDynamicsEnabled(typingDynamicsEnabled)
            controller.setReleaseSoundsEnabled(releaseSoundsEnabled)
            if soundProfile == .custom,
               let id = selectedCustomPackID,
               let pack = customSoundPacks.first(where: { $0.id == id }) {
                controller.setCustomSoundPack(pack) { [weak self] error in
                    guard let error else { return }
                    Task { @MainActor in self?.audioError = error.localizedDescription }
                }
            }
            controller.onHealthChange = { [weak self] error in
                Task { @MainActor in self?.audioError = error }
            }
            if soundEnabled {
                controller.warm()
            }
        } catch {
            audioError = error.localizedDescription
            presentAudioError(error)
        }

        bluetoothMonitor.start()
        if muteDuringCalls { microphoneMonitor.start() }

        let shelf = shelfModel
        shelf.setVisible(!showsMenuBarIcon)
        shelf.start()

        let notchController = NotchWindowController(model: shelf, appDelegate: self)
        self.notchWindowController = notchController
        notchController.show()
        menuBarController = MenuBarController(appDelegate: self)
        applyPresentationMode()
        if showsMenuBarIcon { menuBarController?.showControls() }
        lifecycleMonitor = WorkspaceLifecycleMonitor(
            onSleep: { [weak self] in self?.prepareForSleep() },
            onWake: { [weak self] in self?.recoverAfterWake() }
        )

        updateKeyboardAccess()
        requestKeyboardAccessOnFirstLaunch()
        startAccessChecksIfNeeded()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshLaunchAtLoginStatus()
        updateKeyboardAccess()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        menuBarController?.showControls()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let mediaSleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(mediaSleepObserver) }
        if let mediaWakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(mediaWakeObserver) }
        mediaSubscriptions.removeAll()
        mirror.stop()
        spotify.stop()
        spotifyLibrary.cancel()
        updateChecker.stop()
        lifecycleMonitor?.stop()
        menuBarController?.setVisible(false)
        shelfModel.stop()
        notchWindowController?.stop()
        keyboardMonitor?.stop()
        accessCheckTimer?.invalidate()
        bluetoothAudioMonitor?.stop()
        microphoneActivityMonitor?.stop()
        audioController?.stopSynchronously()
    }

    func playTestSound() {
        guard soundEnabled else { return }
        audioController?.playTestSound()
    }

    func showSettings() {
        mirror.stop()
        shelfModel.closeExplicitly()
        menuBarController?.dismiss()
        if settingsController == nil { settingsController = HarborSettingsController(appDelegate: self) }
        settingsController?.show()
    }

    func dismissFloatingControls() { menuBarController?.dismiss() }

    private func applyPresentationMode() {
        mirror.stop()
        spotify.disappear()
        // Create the alternate entry point before removing the old one.
        if showsMenuBarIcon {
            menuBarController?.setVisible(true)
            shelfModel.setVisible(false)
        } else {
            shelfModel.setVisible(true)
            menuBarController?.setVisible(false)
        }
        updateIslandMusic()
    }

    private func updateIslandMusic() {
        spotify.setIslandMonitoring(preferences.spotifyEnabled && !showsMenuBarIcon)
        shelfModel.hasSpotifyTrack = preferences.spotifyEnabled && spotify.snapshot != nil
        shelfModel.showsNowPlaying = SpotifyIslandPolicy.shouldShow(enabled: preferences.spotifyEnabled, playing: spotify.snapshot?.playing == true, localOutput: spotify.localOutput)
    }

    private func prepareForSleep() {
        spotifyLibrary.cancel()
        mirror.stop()
        spotify.setSuspended(true)
        shelfModel.close()
        menuBarController?.dismiss()
        systemSleeping = true
        keyboardMonitor?.stop()
        keyboardMonitor = nil
        accessCheckTimer?.invalidate()
        accessCheckTimer = nil
        audioController?.suspend()
        bluetoothAudioMonitor?.stop()
        microphoneActivityMonitor?.stop()
    }

    private func recoverAfterWake() {
        systemSleeping = false
        spotify.setSuspended(false)
        // Recreate the event tap even if the old object still existed. Also
        // clears held-key state when key-up was missed while the Mac slept.
        keyboardMonitor?.stop()
        keyboardMonitor = nil
        bluetoothAudioMonitor?.stop()
        microphoneActivityMonitor?.stop()
        bluetoothAudioConnected = bluetoothAudioMonitor?.hasConnectedBluetoothAudioOutput ?? false
        microphoneActive = muteDuringCalls && (microphoneActivityMonitor?.isMicrophoneActive ?? false)
        bluetoothAudioMonitor?.start()
        if muteDuringCalls { microphoneActivityMonitor?.start() }
        audioController?.suspend()
        applyPlaybackState(playTestOnEnable: false)
        // Lazy audio restart on the first input preserves idle suspension.
        updateKeyboardAccess()
        notchWindowController?.recoverAfterWake()
    }

    func toggleSounds() {
        userSoundEnabled.toggle()
        UserDefaults.standard.set(userSoundEnabled, forKey: "soundEnabled")
        applyPlaybackState(playTestOnEnable: true)
    }

    func setVolume(_ newVolume: Double) {
        volume = Self.validVolume(newVolume)
    }

    static func validVolume(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0.72
    }

    func selectSoundProfile(_ profile: KeyboardSoundProfile) {
        guard profile != .custom else { return }
        selectedCustomPackID = nil
        UserDefaults.standard.removeObject(forKey: "selectedCustomPackID")
        audioController?.setCustomSoundPack(nil) { _ in }
        soundProfile = profile
        playTestSound()
    }

    func selectCustomSoundPack(_ pack: CustomSoundPack) {
        audioController?.setCustomSoundPack(pack) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.audioError = error.localizedDescription
                    self.presentSoundPackError(error)
                    return
                }
                self.selectedCustomPackID = pack.id
                UserDefaults.standard.set(pack.id, forKey: "selectedCustomPackID")
                self.soundProfile = .custom
                self.audioError = nil
                self.playTestSound()
            }
        }
    }

    func importCustomSoundPack() {
        guard let customSoundPackLibrary else { return }
        let panel = NSOpenPanel()
        panel.title = "Import NotchHarbor Sound Pack"
        panel.message = "Choose a folder with WAV, AIFF, CAF, or MP3 files. Regular key sounds are required."
        panel.prompt = "Import"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }
        do {
            let pack = try customSoundPackLibrary.importPack(from: sourceURL)
            customSoundPacks = customSoundPackLibrary.availablePacks()
            selectCustomSoundPack(pack)
        } catch {
            presentSoundPackError(error)
        }
    }

    func setPitchVariationEnabled(_ enabled: Bool) { pitchVariationEnabled = enabled }
    func setTypingDynamicsEnabled(_ enabled: Bool) { typingDynamicsEnabled = enabled }
    func setSuppressKeyRepeat(_ enabled: Bool) { suppressKeyRepeat = enabled }
    func setReleaseSoundsEnabled(_ enabled: Bool) { releaseSoundsEnabled = enabled }
    func setMuteDuringCalls(_ enabled: Bool) { muteDuringCalls = enabled }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginManager.setEnabled(enabled)
            refreshLaunchAtLoginStatus()
        } catch {
            refreshLaunchAtLoginStatus()
            presentLaunchAtLoginError(error)
        }
    }

    func setShowsMenuBarIcon(_ shows: Bool) {
        showsMenuBarIcon = shows
        if shows {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.showsMenuBarIcon else { return }
                self.menuBarController?.showControls()
            }
        }
    }

    func requestKeyboardAccess() {
        UserDefaults.standard.set(true, forKey: "didRequestInputMonitoring")
        hasKeyboardAccess = CGRequestListenEventAccess()
        updateKeyboardAccess()
        startAccessChecksIfNeeded()
    }

    func openKeyboardSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func requestKeyboardAccessOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: "didRequestInputMonitoring") else { return }
        requestKeyboardAccess()
    }

    private func startAccessChecksIfNeeded() {
        guard !systemSleeping, soundEnabled, !hasKeyboardAccess, accessCheckTimer == nil else { return }
        accessCheckTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.accessCheckTimer = nil
                self?.updateKeyboardAccess()
            }
        }
    }

    private func updateKeyboardAccess() {
        guard !systemSleeping else { return }
        let accessGranted = CGPreflightListenEventAccess()
        hasKeyboardAccess = accessGranted

        if accessGranted {
            if soundEnabled {
                installKeyboardMonitorIfNeeded()
            }
        } else if keyboardMonitor != nil {
            keyboardMonitor?.stop()
            keyboardMonitor = nil
        }
        if hasKeyboardAccess {
            accessCheckTimer?.invalidate()
            accessCheckTimer = nil
        } else {
            startAccessChecksIfNeeded()
        }
    }

    private func installKeyboardMonitorIfNeeded() {
        guard keyboardMonitor == nil, let audioController else { return }

        let monitor = GlobalKeyboardMonitor { input in
            audioController.handle(input)
        }
        monitor.suppressKeyRepeat = suppressKeyRepeat

        if monitor.start() {
            keyboardMonitor = monitor
        } else {
            hasKeyboardAccess = false
        }
    }

    private func handleAudioTopologyChange(bluetoothAudioConnected isConnected: Bool) {
        let bluetoothStateChanged = bluetoothAudioConnected != isConnected
        bluetoothAudioConnected = isConnected
        applyPlaybackState(
            playTestOnEnable: false,
            rebuildAudioRoute: !bluetoothStateChanged
        )
    }

    private func handleMicrophoneActivityChange(_ active: Bool) {
        microphoneActive = active
        applyPlaybackState(playTestOnEnable: false)
    }

    private func configureMicrophoneMonitoring() {
        guard let microphoneActivityMonitor else { return }
        if muteDuringCalls {
            microphoneActive = microphoneActivityMonitor.isMicrophoneActive
            microphoneActivityMonitor.start()
        } else {
            microphoneActivityMonitor.stop()
            microphoneActive = false
        }
        applyPlaybackState(playTestOnEnable: false)
    }

    private func applyPlaybackState(
        playTestOnEnable: Bool,
        rebuildAudioRoute: Bool = false
    ) {
        guard !systemSleeping else { return }
        let shouldEnable = PlaybackPolicy.shouldEnable(
            userEnabled: userSoundEnabled,
            bluetoothAudioConnected: bluetoothAudioConnected,
            muteDuringCalls: muteDuringCalls,
            microphoneActive: microphoneActive
        )

        if shouldEnable != soundEnabled {
            soundEnabled = shouldEnable
            if shouldEnable {
                audioController?.warm()
                updateKeyboardAccess()
                startAccessChecksIfNeeded()
                if playTestOnEnable {
                    playTestSound()
                }
            } else {
                keyboardMonitor?.stop()
                keyboardMonitor = nil
                accessCheckTimer?.invalidate()
                accessCheckTimer = nil
                audioController?.suspend()
            }
        } else if shouldEnable && rebuildAudioRoute {
            audioController?.rebuildAudioRoute()
        }
    }

    private func presentAudioError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "NotchHarbor could not start audio"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func refreshLaunchAtLoginStatus() {
        launchAtLogin = LaunchAtLoginManager.isEnabled
    }

    private func presentLaunchAtLoginError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Launch at Login could not be changed"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func presentSoundPackError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "The sound pack could not be imported"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func savedBool(
        _ defaults: UserDefaults,
        key: String,
        defaultValue: Bool
    ) -> Bool {
        defaults.object(forKey: key) == nil ? defaultValue : defaults.bool(forKey: key)
    }
}
