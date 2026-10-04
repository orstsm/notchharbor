# NotchHarbor 2.17.1

- The collapsed island shows Spotify artwork and playback bars only while Spotify reports playing **and** macOS confirms a Spotify-owned process has active output on this Mac. Remote Spotify Connect playback no longer qualifies merely because the Desktop app reports playing.
- Paused, inactive or unconfirmed output hides all Spotify decoration from the collapsed island. Hover/click still opens Music with the retained song, artwork and controls.
- Local playback detection uses Core Audio process/device notifications and a single settling check after a change, not a recurring poll. It reads run-state only; no audio tap, recording, samples, microphone access or new Spotify credentials.
- On macOS before 14.2, or if local-output state cannot be read, the collapsed playback indicator stays hidden. Desktop controls and deliberate hover remain available.

Keyboard audio, playlist authorization and camera behavior are unchanged. Community build is ad-hoc signed, not Apple-notarized. Renewed Input Monitoring or Automation permission may be required after replacement.
