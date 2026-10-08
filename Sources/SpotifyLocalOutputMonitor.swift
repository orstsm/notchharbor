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

struct SpotifyOutputProperty: Hashable {
    let object: AudioObjectID
    let selector: AudioObjectPropertySelector
    let topology: Bool
}

/// Injected HAL boundary for notification-storm and blocked-driver regressions.
struct SpotifyOutputBackend {
    var properties: () -> Set<SpotifyOutputProperty>
    var read: () -> SpotifyLocalOutputState
    var subscribe: (SpotifyOutputProperty, @escaping () -> Void) -> (() -> Void)?
}

/// Only this small lock is touched from listener callbacks and the UI. Never
/// hold it across HAL calls. At most one coalesced evaluation is queued.
private final class SpotifyOutputGate {
    private let lock = NSLock()
    private var active = false
    private var generation = 0
    private var pending = false
    private var topology = false
    func activate() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !active else { return false }
        active = true; generation += 1
        return true
    }
    func invalidate() {
        lock.lock(); defer { lock.unlock() }
        active = false; generation += 1; pending = false; topology = false
    }
    func request(topology changed: Bool) -> Int? {
        lock.lock(); defer { lock.unlock() }
        guard active else { return nil }
        topology = topology || changed
        guard !pending else { return nil }
        pending = true
        return generation
    }
    func take(_ ticket: Int) -> Bool? {
        lock.lock(); defer { lock.unlock() }
        guard active, generation == ticket else { return nil }
        let result = topology
        topology = false; pending = false
        return result
    }
    func current(_ ticket: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return active && generation == ticket
    }
}

/// Event-driven local-output detection. Stable subscriptions and asynchronous
/// teardown prevent the listener rebuild loop / main-thread sleep hang in 2.17.1.
final class SpotifyLocalOutputMonitor {
    private let queue = DispatchQueue(label: "com.notchharbor.spotify-output", qos: .utility)
    private let gate = SpotifyOutputGate()
    private let backend: SpotifyOutputBackend
    private let handler: (SpotifyLocalOutputState) -> Void
    private var listeners: [SpotifyOutputProperty: () -> Void] = [:]
    private var settleWork: DispatchWorkItem?
    private var last: SpotifyLocalOutputState?

    init(backend: SpotifyOutputBackend? = nil, handler: @escaping (SpotifyLocalOutputState) -> Void) {
        self.backend = backend ?? Self.liveBackend
        self.handler = handler
    }
    func start() {
        guard gate.activate() else { return }
        refresh()
    }
    func refresh() {
        schedule(topology: true)
    }
    func stop() {
        // Invalidate immediately; never wait for an audio-driver queue from UI.
        gate.invalidate()
        queue.async { [self] in
            self.settleWork?.cancel()
            self.settleWork = nil
            self.removeListeners()
            self.last = nil
        }
    }
    deinit {
        gate.invalidate()
        settleWork?.cancel()
        // No self capture and no synchronous dispatch from deinit. Any active
        // evaluation retains self, so this snapshot cannot race with mutation.
        let cleanup = Array(listeners.values)
        queue.async { cleanup.forEach { $0() } }
    }

    private func schedule(topology: Bool) {
        guard let ticket = gate.request(topology: topology) else { return }
        queue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.evaluate(ticket)
        }
    }
    private func evaluate(_ ticket: Int) {
        guard let topology = gate.take(ticket) else { return }
        if topology { reconcile(ticket) }
        publish(ticket)
        guard gate.current(ticket) else { return }
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.publish(ticket)
        }
        settleWork = work
        queue.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
    private func publish(_ ticket: Int) {
        guard gate.current(ticket) else { return }
        let current = backend.read()
        guard gate.current(ticket), current != last else { return }
        last = current
        handler(current)
    }
    private func reconcile(_ ticket: Int) {
        let desired = backend.properties()
        guard gate.current(ticket) else { return }
        for key in Set(listeners.keys).subtracting(desired) {
            listeners.removeValue(forKey: key)?()
        }
        for key in desired.subtracting(Set(listeners.keys)) {
            guard gate.current(ticket) else { return }
            if let cancel = backend.subscribe(key, { [weak self] in
                // HAL callback only signals work; never adds/removes listeners.
                self?.schedule(topology: key.topology)
            }) { listeners[key] = cancel }
        }
    }
    private func removeListeners() {
        let cleanup = Array(listeners.values)
        listeners.removeAll()
        cleanup.forEach { $0() }
    }

    private static var liveBackend: SpotifyOutputBackend {
        SpotifyOutputBackend(properties: properties, read: readState, subscribe: subscribe)
    }
    private static func properties() -> Set<SpotifyOutputProperty> {
        guard #available(macOS 14.2, *) else { return [] }
        var result = Set<SpotifyOutputProperty>()
        func add(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, topology: Bool = false) {
            result.insert(SpotifyOutputProperty(object: object, selector: selector, topology: topology))
        }
        let system = AudioObjectID(kAudioObjectSystemObject)
        add(system, kAudioHardwarePropertyProcessObjectList, topology: true)
        add(system, kAudioHardwarePropertyDevices, topology: true)
        add(system, kAudioHardwarePropertyDefaultOutputDevice, topology: true)
        for process in Self.spotifyProcesses() ?? [] {
            add(process, kAudioProcessPropertyIsRunningOutput)
            add(process, kAudioProcessPropertyIsRunning)
            add(process, kAudioProcessPropertyDevices, topology: true)
        }
        for device in Self.ids(system, kAudioHardwarePropertyDevices) ?? [] {
            add(device, kAudioDevicePropertyDeviceIsRunningSomewhere)
        }
        return result
    }
    private static func subscribe(_ key: SpotifyOutputProperty, notify: @escaping () -> Void) -> (() -> Void)? {
        var address = Self.address(key.selector)
        guard AudioObjectHasProperty(key.object, &address) else { return nil }
        // Keep callbacks off the management queue, with stable block identity
        // and the same queue/block supplied to the matching removal.
        let delivery = DispatchQueue.global(qos: .utility)
        let block: AudioObjectPropertyListenerBlock = { _, _ in notify() }
        guard AudioObjectAddPropertyListenerBlock(key.object, &address, delivery, block) == noErr else { return nil }
        return {
            var address = Self.address(key.selector)
            AudioObjectRemovePropertyListenerBlock(key.object, &address, delivery, block)
        }
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
