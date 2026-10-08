import AppKit
import Combine
import CryptoKit
import Network
import Security

struct SpotifyPlaylist: Decodable, Identifiable {
    let id: String
    let name: String
}

enum SpotifyLibrarySecurity {
    static let redirect = "http://127.0.0.1:43829/callback"
    static func validClientID(_ value: String) -> Bool {
        value.count == 32 && value.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
    }
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func challenge(_ verifier: String) -> String { base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))) }
    static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw LibraryError.message("Could not create a secure sign-in session.") }
        return base64URL(Data(bytes))
    }
    static func form(_ values: [String: String]) -> Data {
        let safe = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return Data(values.sorted { $0.key < $1.key }.map { "\($0.key.addingPercentEncoding(withAllowedCharacters: safe)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: safe)!)" }.joined(separator: "&").utf8)
    }
    static func callback(_ target: String, state: String) -> (code: String?, denied: Bool)? {
        guard target.hasPrefix("/callback?"), target.utf8.count <= 8192,
              let parts = URLComponents(string: "http://127.0.0.1:43829" + target), parts.path == "/callback" else { return nil }
        let items = parts.queryItems ?? []
        guard items.filter({ $0.name == "state" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == state else { return nil }
        if items.contains(where: { $0.name == "error" }) { return (nil, true) }
        guard items.filter({ $0.name == "code" }).count == 1,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty, code.count <= 4096 else { return nil }
        return (code, false)
    }
}

private enum LibraryError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// Keychain can wait for securityd or user approval after unlock/re-signing.
/// Never perform these blocking calls on MainActor. Serialize mutations so a
/// disconnect queued after a token save cannot be overtaken by that save.
enum SpotifyCredentialWorker {
    private static let queue = DispatchQueue(label: "com.notchharbor.spotify-keychain", qos: .utility)
    static func perform<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try work()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
}

private enum SpotifyLibraryKeychain {
    static func query(_ client: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.notchharbor.spotify-library", kSecAttrAccount as String: client]
    }
    static func read(_ client: String) async throws -> String? {
        try await SpotifyCredentialWorker.perform { readBlocking(client) }
    }
    private static func readBlocking(_ client: String) -> String? {
        var request = query(client)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ token: String, client: String) async throws {
        try await SpotifyCredentialWorker.perform { try saveBlocking(token, client: client) }
    }
    private static func saveBlocking(_ token: String, client: String) throws {
        let data = Data(token.utf8)
        let result = SecItemUpdate(query(client) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result == errSecSuccess { return }
        guard result == errSecItemNotFound else { throw LibraryError.message("Could not save Spotify access in Keychain.") }
        var request = query(client)
        request[kSecValueData as String] = data
        request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(request as CFDictionary, nil) == errSecSuccess else { throw LibraryError.message("Could not save Spotify access in Keychain.") }
    }
    static func delete(_ client: String) async throws -> Bool {
        try await SpotifyCredentialWorker.perform { deleteBlocking(client) }
    }
    private static func deleteBlocking(_ client: String) -> Bool {
        let result = SecItemDelete(query(client) as CFDictionary)
        return result == errSecSuccess || result == errSecItemNotFound
    }
}

/// Loopback-only, bounded and temporary. No cookies, client secret or Spotify
/// Desktop credentials are read. All browser authorization is user initiated.
@MainActor
final class SpotifyLibrary: ObservableObject {
    @Published var clientID: String
    @Published private(set) var playlists: [SpotifyPlaylist] = []
    @Published private(set) var busy = false
    @Published private(set) var connected: Bool
    @Published private(set) var message = "Connect your Spotify library to browse playlists."
    @Published private(set) var hasMore = false
    @Published private(set) var authorizing = false
    @Published private(set) var needsCredentialAccess = false
    @Published private(set) var hasUnsavedAccess = false
    // Legacy login Keychain can display UI even with no-authentication flags.
    // Only explicit user actions may read/write it. Automatic renewal uses RAM.
    private var refreshToken: String?
    private var saveConnection = true
    private let readCredential: (String) async throws -> String?
    private let saveCredential: (String, String) async throws -> Void
    private let defaults: UserDefaults
    private var storedClient: String { defaults.string(forKey: "harbor.spotifyClientID") ?? "" }
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var operation: Task<Void, Never>?
    private var authTimeout: Task<Void, Never>?
    private var generation = 0
    private var verifier = ""
    private var state = ""
    private var accessToken: String?
    private var expiresAt = Date.distantPast
    private var offset = 0
    private var refreshedAt = Date.distantPast
    private var retryAfter = Date.distantPast

    init(defaults: UserDefaults = .standard,
         readCredential: @escaping (String) async throws -> String? = { try await SpotifyLibraryKeychain.read($0) },
         saveCredential: @escaping (String, String) async throws -> Void = { try await SpotifyLibraryKeychain.save($0, client: $1) }) {
        self.defaults = defaults
        self.clientID = defaults.string(forKey: "harbor.spotifyClientID") ?? ""
        self.connected = defaults.bool(forKey: "harbor.spotifyLibraryConnected")
        self.readCredential = readCredential
        self.saveCredential = saveCredential
    }

    func appear() {
        if connected && Date().timeIntervalSince(refreshedAt) > 300 { refresh() }
    }

    func connect(saveInKeychain: Bool = true) {
        guard !busy else { return }
        let client = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SpotifyLibrarySecurity.validClientID(client) else { message = "Enter the 32-character Client ID from your Spotify developer app—not its secret."; return }
        if connected && client != storedClient { message = "Disconnect the current library before changing Client ID."; return }
        cancel()
        saveConnection = saveInKeychain
        do {
            verifier = try SpotifyLibrarySecurity.random()
            state = try SpotifyLibrarySecurity.random()
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 43829)
            let server = try NWListener(using: parameters)
            listener = server
            busy = true
            authorizing = true
            message = "Finish signing in in your browser."
            let token = generation
            server.stateUpdateHandler = { [weak self] status in
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    switch status {
                    case .ready:
                        var url = URLComponents(string: "https://accounts.spotify.com/authorize")!
                        url.queryItems = [URLQueryItem(name: "client_id", value: client), URLQueryItem(name: "response_type", value: "code"),
                            URLQueryItem(name: "redirect_uri", value: SpotifyLibrarySecurity.redirect), URLQueryItem(name: "state", value: self.state),
                            URLQueryItem(name: "code_challenge_method", value: "S256"), URLQueryItem(name: "code_challenge", value: SpotifyLibrarySecurity.challenge(self.verifier)),
                            URLQueryItem(name: "scope", value: "playlist-read-private playlist-read-collaborative")]
                        if !NSWorkspace.shared.open(url.url!) { self.fail("Could not open your browser. Try again.") }
                    case .failed: self.fail("Could not start local Spotify sign-in. Port 43829 may be in use; try again after closing another sign-in window.")
                    default: break
                    }
                }
            }
            server.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    guard let self, self.generation == token, self.authorizing, self.connections.count < 4 else { connection.cancel(); return }
                    let id = UUID()
                    self.connections[id] = connection
                    connection.start(queue: .main)
                    self.receive(connection, id: id, data: Data(), token: token, client: client)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                        self?.connections.removeValue(forKey: id)?.cancel()
                    }
                }
            }
            server.start(queue: .main)
            authTimeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.fail("Spotify sign-in timed out. Connect again when ready.")
            }
        } catch { fail("Could not start secure Spotify sign-in.") }
    }

    private func receive(_ connection: NWConnection, id: UUID, data: Data, token: Int, client: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] chunk, _, complete, error in
            Task { @MainActor in
                guard let self, self.generation == token, self.authorizing else { connection.cancel(); return }
                var bytes = data
                if let chunk { bytes.append(chunk) }
                guard bytes.count <= 8192, error == nil else { self.connections.removeValue(forKey: id)?.cancel(); return }
                guard let request = String(data: bytes, encoding: .utf8), request.contains("\r\n\r\n") else {
                    if complete { self.connections.removeValue(forKey: id)?.cancel() }
                    else { self.receive(connection, id: id, data: bytes, token: token, client: client) }
                    return
                }
                let line = request.components(separatedBy: "\r\n")[0].split(separator: " ")
                let callback = line.count == 3 && line[0] == "GET" ? SpotifyLibrarySecurity.callback(String(line[1]), state: self.state) : nil
                let body = callback == nil ? "Invalid sign-in callback. Return to NotchHarbor." : "Return to NotchHarbor to finish. You can close this tab."
                let response = "HTTP/1.1 \(callback == nil ? "400 Bad Request" : "200 OK")\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'none'\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
                self.connections.removeValue(forKey: id)
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                guard let callback else { return }
                self.closeListener()
                self.authorizing = false
                if callback.denied { self.fail("Spotify library access was not granted."); return }
                guard let code = callback.code else { return }
                let verifier = self.verifier
                let saveConnection = self.saveConnection
                self.operation = Task { [weak self] in
                    guard let self else { return }
                    do {
                        try await self.exchange(["grant_type": "authorization_code", "code": code, "redirect_uri": SpotifyLibrarySecurity.redirect, "client_id": client, "code_verifier": verifier], client: client, generation: token)
                        if saveConnection, let renewal = self.refreshToken {
                            try await self.saveCredential(renewal, client)
                            guard self.generation == token, !Task.isCancelled else { return }
                            self.hasUnsavedAccess = false
                        }
                        guard self.generation == token, !Task.isCancelled else { return }
                        self.defaults.set(client, forKey: "harbor.spotifyClientID")
                        self.defaults.set(saveConnection, forKey: "harbor.spotifyLibraryConnected")
                        self.clientID = client
                        self.connected = true
                        self.needsCredentialAccess = false
                        self.busy = false
                        self.verifier = ""
                        self.state = ""
                        self.refresh()
                    } catch { if self.generation == token && !Task.isCancelled { self.fail(error.localizedDescription) } }
                }
            }
        }
    }

    func cancel() {
        generation += 1
        operation?.cancel()
        operation = nil
        closeListener()
        busy = false
        authorizing = false
        verifier = ""
        state = ""
    }
    private func closeListener() {
        listener?.cancel()
        listener = nil
        authTimeout?.cancel()
        authTimeout = nil
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
    }
    private func fail(_ text: String) { cancel(); message = text }

    /// The only saved-token read path. Opening Music, refresh, wake and pagination
    /// never call this method. Refusal is not retried until the next button click.
    func authorizeSavedAccess() {
        guard connected, !busy else { return }
        let token = generation
        let client = storedClient
        busy = true
        message = "Approve the macOS Keychain prompt, or choose Deny and sign in without Keychain."
        operation = Task { [weak self] in
            guard let self, self.generation == token, !Task.isCancelled else { return }
            do {
                let saved = try await self.readCredential(client)
                guard self.generation == token, !Task.isCancelled else { return }
                guard let saved, !saved.isEmpty else { throw LibraryError.message("Saved access was not unlocked. You can sign in without Keychain instead.") }
                self.refreshToken = saved
                self.needsCredentialAccess = false
                self.hasUnsavedAccess = false
                self.busy = false
                self.refresh()
            } catch {
                guard self.generation == token, !Task.isCancelled else { return }
                self.busy = false
                self.needsCredentialAccess = true
                self.message = "Saved access was not unlocked. You can sign in without Keychain instead."
            }
        }
    }

    func rememberAccess() {
        guard !busy, let renewal = refreshToken, hasUnsavedAccess else { return }
        let token = generation
        let client = storedClient
        busy = true
        message = "Saving library access. macOS may request Keychain approval."
        operation = Task { [weak self] in
            guard let self, self.generation == token, !Task.isCancelled else { return }
            do {
                try await self.saveCredential(renewal, client)
                guard self.generation == token, !Task.isCancelled else { return }
                self.defaults.set(true, forKey: "harbor.spotifyLibraryConnected")
                self.hasUnsavedAccess = false
                self.busy = false
                self.message = "Library access saved."
            } catch {
                guard self.generation == token, !Task.isCancelled else { return }
                self.busy = false
                self.message = "Could not save access. Playlists remain available for this session."
            }
        }
    }
    func disconnect() {
        guard !busy else { return }
        cancel()
        let token = generation
        let client = storedClient
        busy = true
        message = "Removing library access from Keychain…"
        operation = Task { [weak self] in
            let removed = (try? await SpotifyLibraryKeychain.delete(client)) == true
            guard let self, self.generation == token, !Task.isCancelled else { return }
            self.busy = false
            guard removed else { self.message = "Could not remove the saved credential from Keychain. Try again when unlocked."; return }
            self.connected = false
            self.defaults.set(false, forKey: "harbor.spotifyLibraryConnected")
            self.playlists = []
            self.hasMore = false
            self.accessToken = nil
            self.refreshToken = nil
            self.needsCredentialAccess = false
            self.hasUnsavedAccess = false
            self.expiresAt = .distantPast
            self.message = "Library disconnected. You can also revoke access in your Spotify account's Apps page."
        }
    }

    func refresh() { load(reset: true) }
    func loadMore() { if hasMore { load(reset: false) } }
    private func load(reset: Bool) {
        guard connected, !busy else { return }
        guard refreshToken != nil || (accessToken != nil && expiresAt > Date().addingTimeInterval(60)) else {
            needsCredentialAccess = true
            message = "Playlists are locked. Unlock saved access or sign in without Keychain. Other controls still work."
            return
        }
        guard Date() >= retryAfter else { message = "Spotify requested a short wait before refreshing again."; return }
        busy = true
        message = "Loading playlists…"
        let token = generation
        let client = storedClient
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                if self.accessToken == nil || self.expiresAt < Date().addingTimeInterval(60) {
                    guard let refresh = self.refreshToken else { throw LibraryError.message("Unlock saved access to renew playlists.") }
                    try await self.exchange(["grant_type": "refresh_token", "refresh_token": refresh, "client_id": client], client: client, generation: token)
                }
                guard self.generation == token, !Task.isCancelled, let access = self.accessToken else { return }
                var index = reset ? 0 : self.offset
                var collected = reset ? [] : self.playlists
                // Bounded on-demand batches. Larger libraries continue on scroll;
                // never truncate silently or run a background polling loop.
                var more = true
                for _ in 0..<4 {
                    var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/playlists?limit=50&offset=\(index)")!)
                    request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
                    let data = try await self.request(request)
                    struct Page: Decodable { let items: [SpotifyPlaylist?]; let next: String? }
                    let page = try JSONDecoder().decode(Page.self, from: data)
                    guard self.generation == token, !Task.isCancelled else { return }
                    var ids = Set(collected.map(\.id))
                    for playlist in page.items.compactMap({ $0 }) where SpotifyPlaylistID.isValid(playlist.id) && ids.insert(playlist.id).inserted {
                        collected.append(SpotifyPlaylist(id: playlist.id, name: String(playlist.name.prefix(512))))
                    }
                    index += page.items.count
                    more = page.next != nil && !page.items.isEmpty && index < 100_000
                    if !more { break }
                }
                self.playlists = collected
                self.offset = index
                self.hasMore = more
                self.refreshedAt = Date()
                self.message = collected.isEmpty ? "No playlists returned by Spotify." : ""
                self.busy = false
            } catch {
                guard self.generation == token, !Task.isCancelled else { return }
                self.busy = false
                self.message = (error as? LibraryError)?.localizedDescription ?? "Could not load playlists. Check your connection and retry."
            }
        }
    }

    private func exchange(_ values: [String: String], client: String, generation token: Int) async throws {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = SpotifyLibrarySecurity.form(values)
        let data = try await self.request(request)
        struct Token: Decodable { let access_token: String; let expires_in: Double; let refresh_token: String? }
        let reply = try JSONDecoder().decode(Token.self, from: data)
        guard self.generation == token, !Task.isCancelled else { throw CancellationError() }
        guard !reply.access_token.isEmpty else { throw LibraryError.message("Spotify returned invalid access. Connect again.") }
        if let refresh = reply.refresh_token {
            guard !refresh.isEmpty else { throw LibraryError.message("Spotify returned invalid renewal access.") }
            if refresh != refreshToken { hasUnsavedAccess = true }
            refreshToken = refresh
        }
        else if values["grant_type"] == "authorization_code" { throw LibraryError.message("Spotify did not grant renewable library access. Connect again.") }
        guard self.generation == token, !Task.isCancelled else { throw CancellationError() }
        accessToken = reply.access_token
        expiresAt = Date().addingTimeInterval(min(86400, max(0, reply.expires_in)))
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    private func request(_ request: URLRequest) async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 25
        let session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw LibraryError.message("Invalid Spotify response.") }
        if response.statusCode == 429 {
            let seconds = Double(response.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60
            retryAfter = Date().addingTimeInterval(min(86400, max(1, seconds)))
            throw LibraryError.message("Spotify's rate limit was reached. Please wait before refreshing.")
        }
        if response.statusCode == 401 { accessToken = nil; throw LibraryError.message("Spotify authorization expired. Retry to renew it, or reconnect Library.") }
        if response.statusCode == 400 { throw LibraryError.message("Spotify rejected sign-in. Check Client ID and redirect URI, then reconnect Library.") }
        if response.statusCode == 403 { throw LibraryError.message("Spotify denied library access. Check Premium, developer-app allowlist and granted permissions.") }
        guard response.statusCode == 200, response.expectedContentLength <= 1_000_000 else { throw LibraryError.message("Spotify is unavailable. Please retry later.") }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 1_000_000 else { throw LibraryError.message("Spotify response exceeded the safety limit.") }
            data.append(byte)
        }
        return data
    }
}
