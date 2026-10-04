# Music, mirror and presentation controls

## Spotify Desktop

Open Music → Connect Spotify, then approve the macOS Automation prompt. Spotify must be installed, running and signed in. Desktop control does not read Spotify passwords or tokens. Play/pause, previous/next, position, volume, shuffle and repeat use the installed Spotify scripting interface. Optional playlist browsing uses a separate [library connection](SPOTIFY-LIBRARY.md), with renewal access stored in Keychain. Liking tracks, lyrics, web playback and remote Spotify Connect device selection are not included.

Playback notifications trigger refreshes while Music is visible or island mode is enabled after connecting once. There is no recurring Spotify polling. A one-second on-screen progress animation uses the last position locally and pauses with playback. External seeks/volume changes may require Refresh if Spotify does not send a notification. Closing Music in menu-bar-only mode releases observers and cancels work but retains the track/cover in memory. Island mode observes events while collapsed, stops during sleep and refreshes on wake. Paused tracks are retained inside Music but show no collapsed artwork, bars or pause icon. Quitting Spotify also retains the last track as paused; quitting NotchHarbor clears this memory-only cache. Disable the Spotify tab to hide island integration. Collapsed bars require playing metadata plus active Spotify-owned audio output on this Mac; remote or unconfirmed playback stays hidden. Local output uses Core Audio process/device events and one settling read after a change, without audio capture or repeating polling. Before macOS 14.2, local output is unavailable and the collapsed indicator remains hidden. The bars run at five frames per second (not audio analysis), static with Reduce Motion. Scripts have a 20-second deadline and cannot block the audio queue. Playback commands preempt read-only refreshes, use explicit play/pause states, and update the button immediately; failure shows a retry message and freezes the retained track. Cover failures do not disable controls.

The Music view splits compact playback controls and a scrollable playlist pane. A clickable icon from the installed Spotify app sits beside the title. Configure your own Spotify developer Client ID under Music or Settings → Music & Mirror to connect the library. Account setup and live playlist validation remain required; the app does not inherit Spotify Desktop's login for library access. See the setup guide for development-mode limits, permissions and privacy.

If denied, use System Settings → Privacy & Security → Automation, enable Spotify beneath NotchHarbor, then Connect again. A changed community signature can require renewed permission. Spotify is a separate service and is not affiliated with NotchHarbor.

## Camera mirror

Select Mirror, then Start Mirror. Approve camera access when macOS asks. Video is preview-only: no photo/video file output, microphone input or upload. The camera defaults to 640×480 and requests 15 fps if supported. Closing or switching tabs, changing presentation modes, opening Settings, display/system sleep and session lock stop capture. Waking does not restart it. If the camera is disconnected or unavailable, retry manually.

## Settings and layout

The gear opens a separate settings window. Choose menu-bar-only or island mode under General. Appearance adjusts expanded width, accent and animation; Reduce Motion takes precedence. Notch Behavior has hover/click-only opening and bounded dwell/close delay sliders. The physical notch size remains automatic. The menu-bar panel is capped to the current screen and its Keys content scrolls independently of bottom navigation.

## Manual acceptance checklist

- Menu-bar panel: top header and bottom tabs visible on built-in/external displays and scaled resolutions.
- Switch modes repeatedly; reopen from Applications if the menu bar is crowded.
- Music: approve/deny Automation, connect with Spotify closed/open, pause/resume, change track, seek, volume, shuffle/repeat. Check offline fallback and Refresh after an external seek.
- Local indicator: play on this Mac, pause, resume, then transfer to a phone and back. Only local active playback should decorate the collapsed island. While hidden, hovering should still open Music. Also test with another Mac app playing audio so system-wide output cannot be mistaken for Spotify output.
- Mirror: approve/deny Camera; start/stop; switch tabs, close panel, open Settings, sleep/lock. Confirm camera indicator turns off and stays off after wake. Test unavailable/disconnected camera.
- Hover: quick passes, stationary dwell, dragging, explicit close, click-only, Reduce Motion.
- Confirm keyboard sound, Bluetooth pause, microphone pause, stale-event protection and 30-second audio idle suspension remain unchanged.

Automated tests cover preference persistence/bounds, hover timing, popup sizing, stale preview activation tokens, media progress and safe artwork URLs. They do not substitute for camera permission, live Spotify, animation feel, multi-display or overnight sleep tests.
