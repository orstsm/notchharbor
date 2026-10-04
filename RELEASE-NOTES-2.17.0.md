# NotchHarbor 2.17.0

- Paused music retains its last title, artist and cover across panel/tab changes and transient Spotify failures. The collapsed island shows a static pause indicator instead of disappearing.
- Playback commands take priority over background metadata reads. The play/pause control responds immediately and sends explicit play or pause, with serialized commands and coalesced refreshes; controls no longer disable during routine refreshes.
- Compact player on the left and a scrollable playlist pane on the right. A small clickable Spotify app icon beside the title opens Spotify Desktop.
- Optional Spotify library connection: configure your own Spotify developer Client ID and loopback redirect, sign in using PKCE, and browse owned/followed playlists returned by Spotify. Renewal credentials use macOS Keychain; no client secret or Desktop-session scraping. Large libraries load more as you scroll. Selecting a playlist sends its validated URI to Spotify Desktop.
- Library setup and sign-in are required separately from Desktop playback control. The developer app owner needs Spotify Premium and development-mode users must be allowlisted. Live account authorization and playlist playback require user acceptance testing before publishing.

Community build, ad-hoc signed and not notarized by Apple. Replacing it may require renewed Input Monitoring or Automation permission. Keyboard audio behavior is unchanged. No battery-life claim is made.
