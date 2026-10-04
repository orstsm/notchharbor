import CoreAudio
import Foundation

enum SpotifyLocalOutputState: Equatable {
    case active, inactive, unavailable
}

enum SpotifyIslandPolicy {
    static func shouldShow(enabled: Bool, playing: Bool, localOutput: SpotifyLocalOutputState) -> Bool {
        enabled && playing && localOutput == .active
    }
    static func isSpotify(_ bundleID: String) -> Bool {
        bundleID == "com.spotify.client" || bundleID.hasPrefix("com.spotify.client.helper")
    }
}

/// Reads audio-process run-state only, never samples, captures or taps audio.
/// Spotify's scripting state can describe a remote Connect device. Require
/// Spotify-owned output on this Mac before decorating the collapsed island.
final class SpotifyLocalOutputMonitor {
    private let queue = DispatchQueue(label: "com.notchharbor.spotify-output", qos: .utility)
    private let queueKey = DispatchSpecificKey<Bool>()
    private let handler: (SpotifyLocalOutputState) -> Void
    private var started = false
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var settleWork: DispatchWorkItem?
    private var last: SpotifyLocalOutputState?

    init(handler: @escaping (SpotifyLocalOutputState) -> Void) {
        self.handler = handler
        queue.setSpecific(key: queueKey, value: true)
    }
    func start() {
        queue.async { [weak self] in
            guard let self, !self.started else { return }
            self.started = true
            self.rebuild()
            self.publish()
        }
    }
    func refresh() {
        queue.async { [weak self] in self?.evaluateEvent(rebuild: true) }
    }
    func stop() {
        let cleanup = {
            self.started = false
            self.settleWork?.cancel()
            self.settleWork = nil
            self.removeListeners()
            self.last = nil
        }
        if DispatchQueue.getSpecific(key: queueKey) == true { cleanup() }
        else { queue.sync(execute: cleanup) }
    }
    deinit { stop() }

    private func evaluateEvent(rebuild: Bool) {
        guard started else { return }
        if rebuild { self.rebuild() }
        publish()
        // One bounded settling read for HAL/Spotify transition ordering, not a
        // recurring timer. Device-global events supplement per-process events.
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.started else { return }
            self.publish()
        }
        settleWork = work
        queue.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
    private func publish() {
        guard started else { return }
        let current = Self.readState()
        guard current != last else { return }
        last = current
        handler(current)
    }
    private func rebuild() {
        removeListeners()
        guard #available(macOS 14.2, *) else { return }
        let system = AudioObjectID(kAudioObjectSystemObject)
        listen(system, kAudioHardwarePropertyProcessObjectList, rebuild: true)
        listen(system, kAudioHardwarePropertyDevices, rebuild: true)
        listen(system, kAudioHardwarePropertyDefaultOutputDevice, rebuild: true)
        for process in Self.spotifyProcesses() ?? [] {
            listen(process, kAudioProcessPropertyIsRunningOutput)
            listen(process, kAudioProcessPropertyIsRunning)
            listen(process, kAudioProcessPropertyDevices, rebuild: true)
        }
        for device in Self.ids(system, kAudioHardwarePropertyDevices) ?? [] {
            listen(device, kAudioDevicePropertyDeviceIsRunningSomewhere)
        }
    }
    private func listen(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, rebuild: Bool = false) {
        var address = Self.address(selector)
        guard AudioObjectHasProperty(object, &address) else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.evaluateEvent(rebuild: rebuild)
        }
        if AudioObjectAddPropertyListenerBlock(object, &address, queue, block) == noErr {
            listeners.append((object, address, block))
        }
    }
    private func removeListeners() {
        for (object, original, block) in listeners {
            var address = original
            AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
        }
        listeners.removeAll()
    }

    static func readState() -> SpotifyLocalOutputState {
        guard #available(macOS 14.2, *), let processes = spotifyProcesses() else { return .unavailable }
        var unknown = false
        for process in processes {
            guard let active = uint32(process, kAudioProcessPropertyIsRunningOutput) else { unknown = true; continue }
            if active == 1 { return .active }
        }
        return unknown ? .unavailable : .inactive
    }
    @available(macOS 14.2, *)
    private static func spotifyProcesses() -> [AudioObjectID]? {
        guard let processes = ids(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList) else { return nil }
        return processes.filter { object in
            var address = address(kAudioProcessPropertyBundleID)
            var value: Unmanaged<CFString>?
            var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
                  let value else { return false }
            return SpotifyIslandPolicy.isSpotify(value.takeRetainedValue() as String)
        }
    }
    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
    private static func ids(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID]? {
        var address = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr,
              size <= 65_536, Int(size) % MemoryLayout<AudioObjectID>.size == 0 else { return nil }
        if size == 0 { return [] }
        var values = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let status = values.withUnsafeMutableBytes { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0.baseAddress!) }
        guard status == noErr else { return nil }
        return Array(values.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }
    private static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }
}
