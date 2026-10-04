import Foundation

@main
struct HarborTests {
    @MainActor static func main() throws {
        let name = "com.notchharbor.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let prefs = HarborPreferences(defaults: defaults)
        let model = ShelfModel(preferences: prefs)
        prefs.openOnHover = false
        model.reportPointerState(inside: true, now: 1)
        model.reportPointerState(inside: true, now: 10)
        precondition(!model.isExpanded && !model.pendingOpen)
        model.openManually()
        precondition(model.isExpanded, "Click-only opening must work")
        model.close()
        prefs.openOnHover = true
        prefs.hoverDelay = 0.6
        model.reportPointerState(inside: true, now: 20)
        model.reportPointerState(inside: true, now: 20.5)
        precondition(!model.isExpanded)
        model.reportPointerState(inside: true, now: 20.61)
        precondition(model.isExpanded)
        prefs.closeDelay = 0.8
        model.reportPointerState(inside: false, now: 21)
        model.reportPointerState(inside: false, now: 21.7)
        precondition(model.isExpanded)
        model.reportPointerState(inside: false, now: 21.81)
        precondition(!model.isExpanded)
        prefs.hoverDelay = .nan
        precondition(prefs.openingDelay == 0.18)
        prefs.closeDelay = -1
        precondition(prefs.closingDelay == 0.1)
        prefs.wideLayout = true
        prefs.accent = "Blue"
        let restored = HarborPreferences(defaults: defaults)
        precondition(restored.wideLayout && restored.accent == "Blue")
        precondition(HarborLayout.popupHeight(available: 380) == 340)
        precondition(HarborLayout.popupHeight(available: 1000) == 420)
        precondition(HarborLayout.popupHeight(available: 1000, music: true) == 310)
        precondition(HarborLayout.collapsedWidth(physicalWidth: 185, playing: false) == 185)
        precondition(HarborLayout.collapsedWidth(physicalWidth: 185, playing: true) == 273)
        model.showsNowPlaying = true
        model.hasSpotifyTrack = true
        model.openManually()
        precondition(model.activePage == .music, "Now playing must open Music directly")
        model.close()
        model.showsNowPlaying = false
        model.openManually()
        precondition(model.activePage == .music, "Paused/remote tracks remain available on deliberate opening")
        model.close()
        model.hasSpotifyTrack = false
        model.openManually()
        precondition(model.activePage == .controls, "Without playback, open keyboard controls")
        model.close()
        for connected in [false, true] {
            for visible in [false, true] {
                for island in [false, true] {
                    for suspended in [false, true] {
                        let expected = connected && !suspended && (visible || island)
                        precondition(SpotifyObservationPolicy.shouldObserve(connected: connected, panelVisible: visible, islandEnabled: island, suspended: suspended) == expected)
                    }
                }
            }
        }
        let activation = PreviewActivation()
        let first = activation.invalidate()
        precondition(activation.isCurrent(first))
        _ = activation.invalidate()
        precondition(!activation.isCurrent(first), "Closing must invalidate delayed camera permission work")
        let second = activation.invalidate()
        precondition(activation.isCurrent(second) && !activation.isCurrent(first))
        let data = #"{"title":"A track","artist":"Artist","album":"Album","artwork":"","playing":true,"duration":200,"position":20,"volume":50,"shuffle":false,"repeating":false,"canShuffle":true,"canRepeat":true}"#.data(using: .utf8)!
        var snapshot = try JSONDecoder().decode(SpotifySnapshot.self, from: data)
        let start = Date(timeIntervalSince1970: 0)
        precondition(snapshot.elapsed(since: start, now: start.addingTimeInterval(5)) == 25)
        precondition(snapshot.elapsed(since: start, now: start.addingTimeInterval(500)) == 200)
        snapshot.playing = false
        precondition(snapshot.elapsed(since: start, now: start.addingTimeInterval(5)) == 20)
        let controller = SpotifyController()
        controller.acceptSnapshot(snapshot)
        controller.disappear()
        precondition(controller.snapshot?.title == "A track" && controller.snapshot?.playing == false, "Closing Music must retain paused metadata")
        controller.setSuspended(true)
        precondition(controller.snapshot?.title == "A track", "Sleep must retain the last track")
        controller.acceptSnapshot(nil)
        precondition(controller.snapshot?.title == "A track", "Transient failure must not erase the track")
        var empty = snapshot
        empty.title = ""
        controller.acceptSnapshot(empty)
        precondition(controller.snapshot?.title == "A track", "Empty Spotify metadata must preserve the paused track")
        precondition(SpotifyCommand.seek(.nan).script == "s.playerPosition = 0.0;")
        precondition(SpotifyCommand.volume(1000).script == "s.soundVolume = 100;")
        precondition(SpotifyCommand.setPlaying(true).script == "s.play();")
        precondition(SpotifyCommand.setPlaying(false).script == "s.pause();")
        var queue = SpotifyRequestQueue()
        queue.enqueue(.refresh)
        queue.enqueue(.refresh)
        queue.enqueue(.setPlaying(true))
        queue.enqueue(.setPlaying(false))
        queue.enqueue(.next)
        precondition(queue.next() == .setPlaying(false), "Latest playback intent must beat metadata")
        precondition(queue.next() == .next)
        precondition(queue.next() == .refresh)
        precondition(queue.next() == nil, "Refresh storms must coalesce")
        precondition(SpotifyCommand.playlist("';boom()").script.isEmpty)
        precondition(SpotifyPlaylistID.isValid("0123456789ABCDEFGHIJKL"))
        precondition(SpotifyArtwork.safeURL("https://i.scdn.co/image/abc") != nil)
        for url in ["http://i.scdn.co/image/abc", "https://evil.example/image/abc", "https://i.scdn.co.evil.example/image/abc", "https://user@i.scdn.co/image/abc", "https://i.scdn.co:443/image/abc", "file:///tmp/art.png", "https://i.scdn.co/image/abc?redirect=1"] {
            precondition(SpotifyArtwork.safeURL(url) == nil)
        }
        print("PASS: preferences, dwell timing, popup/notch sizing, now-playing navigation, observation lifecycle, media progress and artwork URLs")
    }
}
