import Foundation

@main
struct SpotifyLibraryTests {
    private static func signaled(_ semaphore: DispatchSemaphore) -> Bool {
        semaphore.wait(timeout: .now()) == .success
    }
    @MainActor static func main() async throws {
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
        // No real credentials: simulate securityd waiting for a user prompt.
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let read = Task { @MainActor in
            try await SpotifyCredentialWorker.perform {
                precondition(!Thread.isMainThread)
                entered.signal()
                precondition(release.wait(timeout: .now() + 3) == .success)
                return "test-only"
            }
        }
        let deadline = Date().addingTimeInterval(2)
        while !signaled(entered) {
            precondition(Date() < deadline, "Credential worker did not start")
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        // This MainActor continuation must run while the worker remains blocked.
        try await Task.sleep(nanoseconds: 50_000_000)
        release.signal()
        let result = try await read.value
        precondition(result == "test-only")
        enum Expected: Error { case failure }
        do {
            let _: Bool = try await SpotifyCredentialWorker.perform { throw Expected.failure }
            preconditionFailure("Worker swallowed an error")
        } catch Expected.failure { }
        print("PASS: blocked credential work leaves MainActor responsive and propagates results/errors")
        let suite = "notchharbor-keychain-policy-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "harbor.spotifyLibraryConnected")
        defaults.set(String(repeating: "a", count: 32), forKey: "harbor.spotifyClientID")
        var reads = 0
        var writes = 0
        let library = SpotifyLibrary(defaults: defaults, readCredential: { _ in
            reads += 1
            return nil // Rejected or locked: never touch the real Keychain.
        }, saveCredential: { _, _ in writes += 1 })
        for _ in 0..<100 { library.appear(); library.refresh(); library.loadMore() }
        precondition(reads == 0 && writes == 0 && library.needsCredentialAccess && !library.busy)
        library.authorizeSavedAccess()
        while library.busy { try await Task.sleep(nanoseconds: 1_000_000) }
        precondition(reads == 1 && library.needsCredentialAccess)
        for _ in 0..<100 { library.cancel(); library.appear(); library.refresh() }
        precondition(reads == 1 && writes == 0, "Reopen/wake must not retry rejected Keychain requests")
        library.authorizeSavedAccess()
        while library.busy { try await Task.sleep(nanoseconds: 1_000_000) }
        precondition(reads == 2, "Only a new explicit action retries")
        var pending: CheckedContinuation<String?, Never>?
        let canceled = SpotifyLibrary(defaults: defaults, readCredential: { _ in
            await withCheckedContinuation { pending = $0 }
        }, saveCredential: { _, _ in preconditionFailure("Canceled read must not save credentials") })
        canceled.authorizeSavedAccess()
        while pending == nil { try await Task.sleep(nanoseconds: 1_000_000) }
        canceled.cancel()
        pending?.resume(returning: "synthetic-test-value")
        try await Task.sleep(nanoseconds: 20_000_000)
        canceled.appear()
        precondition(canceled.needsCredentialAccess && !canceled.busy, "Discard late authorization after sleep/cancel")
        print("PASS: 100 reopens and wake/cancel cycles never access Keychain; explicit retry only; late authorization discarded")
    }
}
