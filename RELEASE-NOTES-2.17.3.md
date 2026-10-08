# NotchHarbor 2.17.3

- Stops automatic login-Keychain access when Music opens, refreshes, paginates or resumes after sleep. The legacy login Keychain can show authentication UI despite modern no-UI flags, so these paths do not call it at all.
- Adds **Unlock Saved Playlists** as an explicit action. Denial or failure does not automatically retry. Saved tokens are not deleted and Keychain permissions are not relaxed.
- Adds **Sign in without Keychain** for session-only Spotify library authorization. This uses the existing browser PKCE flow and keeps tokens in memory; it does not read or overwrite the saved credential. Sign in again after quitting, or explicitly save access.
- Token renewal uses the in-memory credential. Rotated/new renewal credentials are saved only when the user chooses **Save Access in Keychain…**, avoiding surprise password prompts later. Unsaved rotation may require a new Spotify sign-in after restarting.
- Retains the 2.17.2 sleep/listener and background credential-worker fixes. Keyboard sounds, mirror and Spotify Desktop controls do not require library unlock.
- Regression tests cover 100 reopens, 100 cancel/wake-style cycles, explicit retry after denial, and canceled authorization results, without touching real credentials.

Universal community build; ad-hoc signed, not Apple-notarized. Input Monitoring may need renewed approval after replacement. Live OAuth/Keychain approval and overnight sleep/wake remain user acceptance checks.
