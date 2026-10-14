# Outside-click dismissal — 2.17.4

## Root cause

The app presents the same `NotchView` using three different owners. `NotchWindowController` monitored outside clicks, the menu-bar `NSPopover` used native transient behavior, but `MenuBarController.showControls()` created a persistent `NSWindow` with no outside-click or deactivation dismissal. Finder reopening always chose this third path. This code-confirmed, presentation-dependent gap explains why apparently identical controls had different dismissal policies. The UI connection continued to expose the 2.17.3 Controls window after a Finder interaction, but its tendency to surface/reopen app windows prevents treating that observation as an independent physical-click reproduction.

The island also used the current pointer location rather than the click's location, had no app-switch/Space fallback, treated auxiliary-window interaction as outside hover and closed without the explicit-close re-entry latch. These are additional failure paths addressed here; they were not all reproduced in the original live session.

## Implementation

`PanelDismissalMonitor` owns a local/global mouse-only monitor pair while an expanded surface is presented. It also observes app deactivation, another app becoming active, Space changes and display sleep. Local events addressed to an app window pass through untouched. Windowless events are checked against the surface and visible auxiliary windows; menu tracking protects local menu events and hover. Click coordinates are converted to AppKit screen coordinates, including negative/secondary-display coordinates. It does not depend on becoming key, does not intercept keyboard events and does not request permissions.

Dismissal unregisters its observers/monitors before invoking the owner, making duplicate callbacks harmless. Generations reject events from a previous presentation. The island closes through `ShelfModel.closeExplicitly()` and its existing frame animation; an animation generation prevents an obsolete completion from unlocking a later transition. The separate Controls window and status popover dismiss through their existing owner. Hidden compact-island click-to-open monitoring remains separate from expanded outside-click monitoring.

## Validation

- Automated: 100 repeated open/inside/child/outside/duplicate-click cycles; no monitor accumulation; original local event preserved; menu tracking; windowless clicks; negative display coordinates; app resignation; other-app activation; Space/sleep notifications; stale monitor callbacks; window-close cleanup.
- Existing hover tests exercise 100 dwell/close cycles and explicit-close re-entry behavior.
- Full automated suite passed, including existing sound, media, permission-lifecycle and hover tests. Universal arm64/x86_64 build, signature, bundle allowlist, credential scan and ZIP verification passed.
- Installed 2.17.4 (build 39) with permission, preserving a rollback copy. On October 14, 2026, the installed executable matched the tested build byte-for-byte and its deep/strict signature verification passed.
- User-confirmed repeated live acceptance on October 14, 2026: after being asked to repeat outside clicks approximately 20 times on the island and separate Controls window, the user replied, "Both collapse reliably." This is user-reported acceptance, not an independently instrumented 20/20 count for every destination.
- Live internal-control checks through the UI connection passed: Music, Mirror and Keys navigation; volume 100% -> 95% -> 100%; opening the sound menu and selecting NK Cream; opening Settings. The panel remained available for internal interactions. Camera capture and Spotify authorization were not started as part of this test.
- The local rebuild reported Input Monitoring access needed for keyboard sounds. No additional permission is used or requested by outside-click detection; existing keyboard authorization may need renewal after ad-hoc rebuilds.
- Remaining environment-specific checks: separate menu-bar destination coverage, physical secondary monitor, fullscreen/Mission Control/Space transitions, rapid clicks specifically during animation, and Cmd-Tab. Automated coordinate/notification tests cover their decision paths, not real-world acceptance of each environment.

The app-specific UI connection did not provide reliable observation of desktop-wide dismissal, so physical outside-click acceptance was explicitly handed to the user rather than claimed from app-local automation. Source changes remain uncommitted; no GitHub release was published.
