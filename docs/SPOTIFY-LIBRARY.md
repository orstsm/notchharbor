# Connect your Spotify playlists

Desktop playback controls work without a developer app. Browsing your owned/followed playlists requires a separate Spotify Web API connection; being signed in to Spotify Desktop does not grant this access.

## One-time setup

1. Visit [Spotify's developer dashboard](https://developer.spotify.com/dashboard) and create an app for your personal NotchHarbor integration. The app owner must currently have Spotify Premium. No Apple Developer account is required.
2. Enable Web API and register this exact redirect URI: `http://127.0.0.1:43829/callback`.
3. If using development mode, add the Spotify account you will authorize to the app's allowed users. New development-mode apps currently support up to five users; this is not a general-public library integration.
4. Copy the **Client ID**, never the Client Secret. In NotchHarbor, open Music → Your playlists or Settings → Music & Mirror and paste the Client ID.
5. Choose **Connect Library** to save renewal access in Keychain, or **Sign in without Keychain** to keep access only for this app session. Sign into the intended account in your browser and approve playlist read access. The browser should return to the local callback. Return to NotchHarbor to see the list.

Spotify controls and library access are separate permissions. The playlist account should match the account signed into Spotify Desktop. NotchHarbor does not inspect Desktop credentials to verify that match.

## Browse and play

After restarting NotchHarbor, choose **Unlock Saved Playlists** to read your saved access, or **Sign in without Keychain** to authorize a session without a Keychain password. Merely opening the app never requests Keychain access. If the Mac password prompt is refused or does not work, choose Deny; it will not be retried automatically. Keyboard sounds and Desktop media controls remain usable.

Once unlocked/signed in, playlist refresh and token renewal use memory only. If Spotify rotates renewal access, **Save Access in Keychain…** is available in library setup. Saving is optional and can ask for your Mac login-Keychain password. Unsaved access is lost on app quit; a new browser sign-in may be necessary. Existing saved credentials are not automatically deleted or overwritten by session-only sign-in.

Scroll the right-hand playlist pane and click a playlist to request playback in Spotify Desktop. Spotify must be running and Automation access granted; playback eligibility depends on the account and playlist. The list shows playlists returned by Spotify's current-user API. It is not a list of albums, artists or all saved tracks. Larger libraries load further pages as you scroll, with a visible Load more option. Refresh updates the list manually; reopening Music after five minutes can refresh it. There is no repeating background library polling.

A small Spotify app icon beside the current song title opens Spotify. Pausing preserves the current song/artwork and freezes the progress display. Cached metadata is memory-only and does not survive quitting NotchHarbor itself.

## Privacy and troubleshooting

- PKCE sign-in requires no secret in the app. Renewal access is stored in Keychain only with an explicit save/connect action; session-only access stays in memory. No Spotify password is stored by NotchHarbor.
- Disconnect Library removes local saved access. To revoke the grant on Spotify, remove the app from your Spotify account's Apps page.
- An unavailable callback port, rejected redirect, browser cancellation, denied scope, unavailable Keychain or rate limit is shown as an error. Cancel and reconnect if needed.
- If Spotify returns 403, check Premium, the development-mode user allowlist and playlist permissions. If 401 persists after retry, reconnect.
- No browser sign-in is started automatically. Sign-in is canceled on system/display sleep. Keyboard playback remains independent.

## Acceptance before release

The local security/unit checks do not prove live account integration. Verify successful and denied/canceled login, multiple playlist pages, private/followed playlists, selecting a playlist, token renewal, offline fallback, rate limits and disconnect. Until that is done, do not claim automatic library sync is live-tested or publish it as a verified public integration.

References: [PKCE flow](https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow), [redirect rules](https://developer.spotify.com/documentation/web-api/concepts/redirect_uri), [current-user playlists](https://developer.spotify.com/documentation/web-api/reference/get-a-list-of-current-users-playlists), [development-mode requirements](https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide).
