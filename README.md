# NotchHarbor

Your Mac’s little control space — home of **MechaKeys** keyboard and mouse sounds.

NotchHarbor is the new name for MechaKeys. Version 2.17.3 stops automatic Spotify Keychain prompts, with explicit saved-playlist unlock or session-only Spotify sign-in. It also includes the 2.17.2 sleep-time audio-listener and blocked-Keychain UI fixes. The collapsed indicator still appears only for playback on this Mac; paused tracks remain inside Music. The on-demand mirror, keyboard-sound engine and existing preferences are preserved. See the [rename and upgrade guide](docs/RENAMING.md).

Pause over the notch to turn sounds on or off, choose a profile, change volume, or open settings. NotchHarbor is a standalone app: **NotchShelf and boringNotch are not required**. Turn on **Use Menu Bar Instead of Island** in Settings to use only the menu-bar icon; turn it off in the menu-bar controls to return to the island. The choice is remembered.

Island opening requires a continuous 180 ms hover within the notch area. Quick passes and dragging cancel opening. Expansion and collapse animate with the panel bounds and respect Reduce Motion. Hover monitoring stops entirely in menu-bar mode; island mode uses mouse events and cancellable one-shot timers, not continuous polling.

If neither interface is accessible, reopen **NotchHarbor.app** from Applications to show the independent controls window. Its title shows the running version. Menu-bar mode also opens this window on launch or when selected, since macOS may obscure icons on a crowded menu bar. Close the window to keep NotchHarbor running in the background.

## Download and install

Open [GitHub Releases](https://github.com/orstsm/notchharbor/releases) and download the versioned **universal-community.zip** app asset. Unzip it and move **NotchHarbor.app** to Applications. GitHub's automatic “Source code” ZIP is for developers, not an installer. If no release is listed, a downloadable build has not been published yet.

- **Requirements:** macOS 13 or newer; Apple Silicon or Intel Mac. The notch interface is designed for MacBooks with a physical notch.
- **Permission:** enable NotchHarbor in System Settings → Privacy & Security → Input Monitoring for keyboard and mouse sounds.
- **Community build:** ad-hoc signed and **not notarized by Apple**. macOS may block opening or require explicit per-app approval. Only install if you trust the project; never disable Gatekeeper or other system-wide protections. Updates may require Input Monitoring approval again.

See [installation and troubleshooting](INSTALL.md). Downloaded builds do not require Xcode or developer tools.

## Features

- **Music tab:** compact Spotify Desktop controls on the left and an optional scrollable playlist library on the right. Paused tracks retain their artwork. The icon beside the title opens Spotify. Playback uses your desktop login and macOS Automation permission; playlist syncing separately requires your Spotify developer Client ID and browser authorization. See [setup](docs/SPOTIFY-LIBRARY.md).
- **Mirror tab:** explicitly start a circular, horizontally mirrored preview. Stops on tab changes, closing, display sleep or session lock; does not resume automatically. No microphone input, recording or uploads.
- **Sidebar settings:** General, Appearance, Notch Behavior, Keyboard Sounds, Music & Mirror, and Updates. Adjust accent, expanded width, animation, hover opening and opening/closing delays. Disable hover for click-only opening; default dwell remains 180 ms.
- **Screen-bounded menu controls:** a capped-height panel with scrolling controls and persistent bottom navigation, instead of the old oversized popover.

- **Notch controls:** event-driven hover, sound toggle, profile selection, volume, test playback, About, settings and Quit.
- **Recorded and custom profiles:** Default, K Pro Red, Alpaca, Holy Panda, MX Blue, MX Brown, NK Cream and Typewriter, plus validated user-imported sound packs stored in Application Support.
- **Special sounds:** K Pro Red includes regular-key, Space and mouse samples; Alpaca additionally includes Delete/Backspace samples. Default shares four recorded variations across inputs.
- **Spatial panning:** left and right keyboard regions subtly pan toward the corresponding speaker.
- **Bluetooth audio pause:** pauses for connected Bluetooth audio devices and resumes when they disconnect, provided sounds were manually enabled. Bluetooth mice and keyboards do not trigger this pause.
- **Natural dynamics:** optional subtle pitch variation, typing-speed response, held-key repeat suppression and custom-pack release sounds.
- **Call-aware pause:** optionally pauses while a microphone is active using Core Audio property events—no repeating microphone poll.
- **Low-latency playback:** all active sounds are preloaded into the existing polyphonic engine with stale-event dropping. Audio stops after 30 seconds without input; cold wake retains only the newest key and discards delayed mouse clicks.
- **Convenience:** launch at login, remembered preferences and optional menu-bar access.
- **Sleep recovery:** keyboard monitoring and audio-device state are refreshed on system wake/session reactivation, with one settling check rather than continuous polling. Playback does not require an internet connection.
- **Update checks:** Settings → Check for Updates, plus optional daily checks (off by default). Downloads and installation remain manual.

## Privacy and energy use

Playback works offline. NotchHarbor observes physical key/button events to play sounds; it does not record typed text, collect analytics, or upload input data. Optional update checks contact GitHub for public release information. See [security and privacy](SECURITY.md).

Spotify control uses playback events while Music is visible or island mode is enabled, after a successful connection. Collapsed artwork/bars require both a playing track and confirmed Spotify audio output on this Mac. Paused, remote and unconfirmed playback leave the collapsed island undecorated; hover still opens Music with the retained track. Core Audio process/device events detect local output without recording or polling. On macOS before 14.2, the collapsed music indicator stays hidden because local output cannot be confirmed. Observation stops during sleep and refreshes on wake. Album artwork is fetched only from `https://i.scdn.co/image/…`, without cookies, redirects or a disk cache, with a 2 MB limit. Visible progress is calculated locally. Optional playlist access contacts Spotify's authorization/API services, stores renewal access in Keychain, and refreshes on opening Music when stale or on manual request—not on a repeating timer. The camera uses a 640×480 preview, requesting 15 fps when supported. These optional features use extra energy while active; no new battery-drain measurement is claimed. See [media setup and acceptance checks](docs/MEDIA.md).

Hover has no repeating pointer-polling timer, and audio suspends after 30 seconds of inactivity. An idle test confirmed release of the audio sleep assertion, but **no app-specific battery-drain percentage has been established**. See [battery measurements and test procedure](docs/BATTERY-TEST.md).

## Build from source

Install Xcode Command Line Tools, then run these commands from the repository folder:

```sh
zsh Tests/run.sh
zsh build.sh --build-only
# Quit NotchHarbor before installing the new build.
zsh install.sh
```

Building does not replace your installed app. The explicit installer uses your user Applications folder and preserves the previous version for recovery.

## Publish an update from GitHub Desktop

Update the version and release notes, commit/push the changes, then create and push the matching version tag from **History** (for example `v2.17.3`). GitHub Actions tests, builds and publishes the universal community ZIP, installation instructions and checksums. Ordinary commits do not publish releases. Complete live Spotify library and overnight sleep/wake acceptance checks before publishing this version.

Follow the [release checklist](docs/UPDATES.md), including how to check build failures. No paid Apple Developer account is needed for community releases. The optional `release.sh` supports notarized releases when you have the required Apple credentials.

## Repository guide

| Location | Purpose |
| --- | --- |
| `Sources/` | Current app code: notch UI, audio, Bluetooth, permissions, updates |
| `Resources/` | App icons and 83 active sound recordings |
| `Tests/` | Regression tests and installation verification utility |
| `docs/` | Release instructions, reliability notes and battery evidence |
| `.github/workflows/` | Automated tests and tag-triggered community releases |
| Root scripts and plists | Build, package, install, identity and privacy configuration |

`.build/` and `dist/` are local generated output, ignored by Git—not files users need to commit. Release downloads belong in GitHub Releases, not in the source tree.

The Holy Panda, MX Blue, MX Brown, NK Cream and Typewriter recordings are included by private permission from their rights holder. All audio rights are reserved: the recordings may be used only as part of NotchHarbor and may not be extracted, copied, repackaged, reused or redistributed separately.

Custom pack creators should follow the validated format in [docs/CUSTOM-SOUND-PACKS.md](docs/CUSTOM-SOUND-PACKS.md). Imported packs are limited to short local WAV, AIFF, CAF, or MP3 files; scripts and executable content are never copied.

Built by **orstsm**.
