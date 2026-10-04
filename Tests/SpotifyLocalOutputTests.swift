import Foundation

@main
struct SpotifyLocalOutputTests {
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
    }
}
