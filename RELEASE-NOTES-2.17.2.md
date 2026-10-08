# NotchHarbor 2.17.2

- Fixes a confirmed sleep-time UI hang: the main thread was synchronously waiting for the Spotify local-output queue while Core Audio listeners were repeatedly removed and added.
- Keeps unchanged listeners registered, reconciles only actual topology differences, and coalesces notification bursts into one pending evaluation. Listener callbacks never modify registrations directly.
- Stops monitoring without blocking the interface, immediately invalidates old work, and cleans up registrations asynchronously. Late pre-sleep results cannot reactivate the island.
- Fixes a second confirmed UI hang when playlist loading waits for Keychain after an update/unlock. Credential reads, writes and removal now run on a serial background queue; late results are ignored after cancellation. macOS approval is still required when prompted, and credentials remain in Keychain.
- Preserves local-Mac-only playback decoration, hidden paused state, Spotify library credentials, keyboard sounds, mirror privacy and the 30-second audio-idle policy. No new recurring polling.
- Regression coverage includes 10,000 simulated notifications, registration-generated callbacks, idle silence, 20 stop/start cycles, topology changes, blocked audio reads and stale-result rejection.
- A blocked-credential regression verifies that the main actor remains responsive while the credential worker waits, without accessing real credentials.

These tests do not substitute for a full overnight sleep/wake test on each Mac. Community build remains ad-hoc signed and not Apple-notarized. A local replacement may require renewed Input Monitoring approval.
