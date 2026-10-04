import Foundation

@main
struct SpotifyLibraryTests {
    static func main() throws {
        precondition(SpotifyLibrarySecurity.validClientID(String(repeating: "a", count: 32)))
        for bad in ["", "secret", String(repeating: "g", count: 32), String(repeating: "a", count: 33)] {
            precondition(!SpotifyLibrarySecurity.validClientID(bad))
        }
        // RFC 7636 S256 test vector.
        precondition(SpotifyLibrarySecurity.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let first = try SpotifyLibrarySecurity.random()
        let second = try SpotifyLibrarySecurity.random()
        precondition(first.count == 43 && first != second && !first.contains("="))
        precondition(SpotifyLibrarySecurity.callback("/callback?state=correct&code=one", state: "correct")?.code == "one")
        precondition(SpotifyLibrarySecurity.callback("/callback?state=correct&error=access_denied", state: "correct")?.denied == true)
        for target in ["/callback?state=wrong&code=one", "/callback?code=one", "/callback?state=correct&state=correct&code=one", "/callback?state=correct&code=one&code=two", "/callback?state=correct&code=", "/other?state=correct&code=one", "https://evil.example/callback?state=correct&code=one"] {
            precondition(SpotifyLibrarySecurity.callback(target, state: "correct") == nil, "Reject callback: \(target)")
        }
        let encoded = String(data: SpotifyLibrarySecurity.form(["code": "a+b&c=d /", "state": "safe"]), encoding: .utf8)!
        precondition(encoded == "code=a%2Bb%26c%3Dd%20%2F&state=safe")
        precondition(SpotifyPlaylistID.isValid("0123456789abcdefghijkl"))
        for bad in ["", "spotify:playlist:123", "../etc", String(repeating: "a", count: 23), "123456789012345678901'"] { precondition(!SpotifyPlaylistID.isValid(bad)) }
        print("PASS: Spotify PKCE, random state, exact callback validation, form encoding and playlist ID validation")
    }
}
