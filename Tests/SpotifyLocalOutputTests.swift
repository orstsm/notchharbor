import Foundation

private final class FakeOutput {
    let lock = NSLock()
    let key = SpotifyOutputProperty(object: 1, selector: 2, topology: true)
    let other = SpotifyOutputProperty(object: 3, selector: 4, topology: true)
    var callbacks: [SpotifyOutputProperty: () -> Void] = [:]
    var desired: Set<SpotifyOutputProperty> = []
    var adds = 0
    var removes = 0
    var reads = 0
    var reported = 0
    var blocker: DispatchSemaphore?
    let enteredRead = DispatchSemaphore(value: 0)
    func access<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }
    var backend: SpotifyOutputBackend {
        SpotifyOutputBackend(properties: { self.access { self.desired } }, read: {
            let blocker = self.access { self.reads += 1; return self.blocker }
            if let blocker { self.enteredRead.signal(); blocker.wait() }
            return .active
        }, subscribe: { key, callback in
            self.access { self.adds += 1; self.callbacks[key] = callback }
            // Reproduce the initial notification on registration. The old
            // remove/re-add-all implementation fed this back indefinitely.
            callback()
            return { self.access { self.removes += 1; self.callbacks.removeValue(forKey: key) } }
        })
    }
    func signal(_ count: Int = 1) {
        let callbacks = access { Array(self.callbacks.values) }
        for _ in 0..<count { callbacks.forEach { $0() } }
    }
}

@main
struct SpotifyLocalOutputTests {
    static func wait(_ description: String, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(3)
        while !condition() && Date() < deadline { Thread.sleep(forTimeInterval: 0.005) }
        precondition(condition(), description)
    }
    static func lifecycleTests() {
        let fake = FakeOutput()
        fake.desired = [fake.key]
        var monitor: SpotifyLocalOutputMonitor? = SpotifyLocalOutputMonitor(backend: fake.backend) { _ in
            fake.access { fake.reported += 1 }
        }
        monitor?.start()
        wait("Initial registration must complete") { fake.access { fake.adds == 1 && fake.reads >= 2 } }
        fake.signal(10_000)
        Thread.sleep(forTimeInterval: 0.7)
        precondition(fake.access { fake.adds == 1 && fake.removes == 0 && fake.reads < 12 && fake.reported == 1 }, "Storm must coalesce without listener churn")
        let stable = fake.access { fake.reads }
        Thread.sleep(forTimeInterval: 0.7)
        precondition(fake.access { fake.reads == stable }, "No repeating idle polling")
        _ = fake.access { fake.desired.insert(fake.other) }
        monitor?.refresh()
        wait("Only new property added") { fake.access { fake.adds == 2 } }
        _ = fake.access { fake.desired.remove(fake.key) }
        monitor?.refresh()
        wait("Only removed property detached") { fake.access { fake.removes == 1 } }
        precondition(fake.access { fake.adds == 2 })
        for _ in 0..<20 {
            monitor?.stop()
            wait("Sleep cleanup") { fake.access { fake.callbacks.isEmpty } }
            monitor?.start()
            wait("Wake registers one listener") { fake.access { fake.callbacks.count == 1 } }
        }
        monitor?.stop()
        monitor = nil
        wait("All registrations balanced") { fake.access { fake.adds == fake.removes } }

        let blocked = FakeOutput()
        blocked.desired = [blocked.key]
        let release = DispatchSemaphore(value: 0)
        blocked.blocker = release
        var hanging: SpotifyLocalOutputMonitor? = SpotifyLocalOutputMonitor(backend: blocked.backend) { _ in
            blocked.access { blocked.reported += 1 }
        }
        hanging?.start()
        precondition(blocked.enteredRead.wait(timeout: .now() + 3) == .success)
        let start = ProcessInfo.processInfo.systemUptime
        hanging?.stop()
        hanging = nil
        precondition(ProcessInfo.processInfo.systemUptime - start < 0.1, "UI must not wait for a blocked HAL read or deinit")
        release.signal()
        wait("Blocked worker eventually releases resources") { blocked.access { blocked.callbacks.isEmpty } }
        precondition(blocked.access { blocked.reported == 0 }, "Discard results after stop")
        print("PASS: 10,000 notifications coalesced, stable listener diff, idle silence, 20 sleep/wake cycles, nonblocking stop and stale-result rejection")
    }
    static func main() {
        if CommandLine.arguments.contains("--probe") {
            print("Spotify local output: \(SpotifyLocalOutputMonitor.readState())")
            return
        }
        for enabled in [false, true] {
            for playing in [false, true] {
                for output in [SpotifyLocalOutputState.active, .inactive, .unavailable] {
                    precondition(SpotifyIslandPolicy.shouldShow(enabled: enabled, playing: playing, localOutput: output) == (enabled && playing && output == .active))
                }
            }
        }
        precondition(SpotifyIslandPolicy.isSpotify("com.spotify.client"))
        precondition(SpotifyIslandPolicy.isSpotify("com.spotify.client.helper"))
        for other in ["com.apple.Music", "com.mechakeys.app", "com.spotify.clientfake", "com.browser.spotify"] {
            precondition(!SpotifyIslandPolicy.isSpotify(other))
        }
        print("PASS: island requires local Spotify output and playback; paused, remote, unknown and disabled states stay hidden")
        lifecycleTests()
    }
}
