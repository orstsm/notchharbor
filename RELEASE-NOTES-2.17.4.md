# NotchHarbor 2.17.4

- Share outside-click dismissal between the nonactivating island, menu-bar popover and separate Controls window.
- Observe local/global mouse-down events and application/Space transitions without polling or new permissions.
- Preserve local controls, menus, sheets, child windows and Settings interactions.
- Disarm dismissal before closing, discard stale callbacks and prevent hover reopening during the island's closing animation.
- Keep the island's compact window available; only dismiss the separate floating controls surface.

No changes to the audio engine, Bluetooth handling, keyboard playback, Spotify integration or mirror implementation. No new dependencies or entitlement changes.

See `docs/OUTSIDE-CLICK-VALIDATION.md` for verified tests and remaining live acceptance checks. This community build is ad-hoc signed and not notarized by Apple.
