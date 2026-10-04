# NotchHarbor security model

## Input access

NotchHarbor requests macOS Input Monitoring permission to observe global key-down, key-up and mouse-button-down events. The audio event tap is passive (`listenOnly`) and reads physical key codes and button numbers, not typed text. Key-up state suppresses held-key repeats and can trigger an optional custom-pack release sound. Separately, the notch observes mouse movement and reads the current pointer position locally to open its controls. Pointer positions are not recorded or transmitted. There is no recurring hover polling timer; movement opens the notch and a single exit deadline closes it.

The audio input tap is removed when sounds are off. Mouse movement observation remains available for the notch. NotchHarbor does not reconstruct text, inspect clipboard contents, write input events to disk, or transmit data.

## Data and network

Sound playback works offline and collects no analytics. Manual update checks, or optional daily checks (off by default), request public release metadata from `api.github.com/repositories/1356119654/releases/latest`, the existing repository's stable ID. GitHub receives the connecting IP address and a generic app User-Agent, but no typed text, key codes, pointer positions, sound settings, account tokens, or persistent app-generated identifier. Checks use an ephemeral session without cookies or disk caching, with timeouts, a 1 MiB response limit, and no redirects. Release links must use HTTPS on github.com under `orstsm/notchharbor` or the legacy `orstsm/mechakeys`, with the exact reported version tag and no credentials, ports, queries or fragments. Opening a release uses the user's browser and its normal privacy settings. Nothing is automatically downloaded or installed.

Local preferences in `UserDefaults` include:

- sounds enabled
- volume
- selected switch profile
- whether the Input Monitoring prompt has been shown
- optional menu-bar icon and notch visibility/recovery preferences
- pitch variation, typing dynamics, repeat suppression, release-sound and microphone-pause choices
- the identifier of a selected custom sound pack
- daily-update opt-in and last update-attempt time

The included privacy manifest declares no tracking or collected data.

NotchHarbor reads CoreAudio's local device list to determine whether an available output uses Bluetooth transport. When automatic microphone pause is enabled, it also subscribes to Core Audio device-run-state changes and pauses while any microphone is active. This is event-driven and does not continuously poll. NotchHarbor never opens the microphone or reads, records, stores, or transmits microphone audio. Device identifiers are used only in memory and are never stored or transmitted.

Custom sound packs are stored under the user's Application Support folder. Imports accept only short audio files and recognized metadata, reject symbolic links and enforce file-count, size and duration limits. Files are copied through a staging folder and validated again before activation. Imported audio remains local and is never uploaded.

The included Holy Panda, MX Blue, MX Brown, NK Cream and Typewriter recordings are immutable application resources loaded from the signed bundle. They are included by private permission from their rights holder and are not licensed for extraction, reuse, repackaging or separate redistribution.

## Optional music and camera

The collapsed Spotify indicator additionally requires a Spotify-owned Core Audio process with active output on this Mac. The monitor reads bundle identifiers and boolean run-state in memory; it never captures samples, creates audio taps, requests microphone/screen recording permission or transmits process information. Process-list, device and run-state notifications trigger reads, with one bounded settling read after a change. Paused/remote/unconfirmed output hides collapsed music decoration. If process-state support is unavailable (including macOS before 14.2), the indicator fails closed while deliberate Music controls remain available.

Spotify Desktop integration starts with an explicit Connect action. Fixed local scripting commands run off the UI/audio queues in a bounded helper process. Track metadata is never interpolated into scripts; numeric arguments are clamped and playlist IDs must be exactly 22 ASCII alphanumeric characters. Explicit playback commands take priority over read-only metadata requests. Playback-change notifications are observed while Music is visible or the Spotify-enabled island is active; no recurring metadata polling. Connection consent is remembered, sleep cancels observation, and wake refreshes once. Last-track metadata and cover art stay in memory across pause/closure but are not persisted to disk. Artwork requests go only to HTTPS `i.scdn.co/image/…`, without redirects, cookies or disk caching, and stop at 2 MB. Spotify receives the connecting IP address and artwork identifier, not keyboard input. Desktop controls do not read Spotify passwords, cookies or credentials.

Optional playlist browsing uses a separate, user-initiated OAuth authorization-code flow with PKCE/S256. No client secret is used. The public Client ID and connection preference are saved in UserDefaults; the refresh token is stored in a dedicated local macOS Keychain item and the access token stays in memory. The callback listener binds only to `127.0.0.1:43829`, checks a cryptographically random state and exact callback path, limits request size/connections, and stops on completion, cancellation, sleep or a five-minute timeout. Token requests go only to `https://accounts.spotify.com/api/token`; playlist reads go only to `https://api.spotify.com/v1/me/playlists`. Requests use bounded ephemeral sessions without redirects or cookies, a 1 MB response cap, and rate-limit backoff. Server-provided pagination URLs are never followed: offsets are constructed locally. Lists are retained only in memory; no playlist data is sent to the developer. Disconnect removes this app's local renewal credential, but users must revoke the grant from Spotify's Apps page to revoke it server-side. Browser login uses the user's normal browser session. No account or live library authorization has been verified until the user's setup and acceptance test is complete.

Camera permission is requested only after Start Mirror. The capture session has video input and preview only: no audio input, photo/movie output, storage or upload. Capture stops when hidden, on mode changes, display/system sleep and session lock. Pending permission/configuration work is invalidated when the surface closes. Camera never automatically resumes after waking.

The hardened runtime includes camera and Apple Events entitlements for these opt-in features. It does not disable library validation or executable-memory protections.

## Repository and packaging safeguards

`python3 scripts/security_check.py --history` checks commit-eligible working files, staged Git blobs, and all locally reachable history for known credential patterns. CI fetches full history and runs this check before builds/releases. The scanner also rejects credential filenames and unpinned external workflow actions. Reports show paths/object IDs and rule names, not matching values. It is an offline, dependency-free defense-in-depth check; it cannot recognize every arbitrary, encoded or encrypted secret and is not a security certification. It never accesses Keychain or personal preferences. Ignored credential files remain local; force-added files are still checked.

Every build starts with a fresh temporary app bundle, retains the previous build until verification succeeds, and validates an exact file allowlist (`scripts/bundle-files.txt`). Unexpected files, links, missing resources and source/resource mismatches block the build. Credentials are scanned in the executable and resources too. The community ZIP is extracted and checked again after packaging. New legitimate resources require a reviewed allowlist update. The local source exporter copies only checked, commit-eligible files and explicitly excludes private license documents instead of copying whole development directories.

GitHub Actions checkout is pinned to its full upstream commit and does not retain Git credentials. A full-history scan covers locally fetched refs, not deleted GitHub refs, caches or previously downloaded releases. Keep repository access protected with MFA and review every release diff. No automated check guarantees that software is 100% secure.

### Signing and notarization

The optional notarized release path uses a Developer ID Application certificate, hardened runtime, a secure timestamp, and Apple notarization. `release.sh` refuses to run without a signing identity and notary keychain profile. The community workflow instead uses ad-hoc signing with hardened runtime and the feature-specific entitlements described above.

Community builds are ad-hoc signed and are not notarized by Apple. Shared community releases must prominently disclose that limitation. macOS may block opening them or require explicit per-app approval; users must not disable Gatekeeper or other system-wide security protections.

## Launch at login

When installed in `/Applications` or the user's `Applications` folder, NotchHarbor uses Apple's `SMAppService.mainApp`. Legacy LaunchAgents are retained until migration is approved, then removed. Development copies elsewhere use a user-owned LaunchAgent with mode `0600`, launching the app through `/usr/bin/open` without a shell or elevated privileges.

Building and packaging never replace an installed application. The separate installer verifies a staged bundle, refuses to replace a running app, and uses a same-volume atomic exchange with a preserved rollback copy. Shared ad-hoc builds must disclose their community status without implying Apple notarization or verified developer identity.
