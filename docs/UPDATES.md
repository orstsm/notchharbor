# Publishing updates

## NotchHarbor rename (2.15.0)

The repository was renamed from `orstsm/mechakeys` to `orstsm/notchharbor`, preserving history. Existing clones should update their remote to `https://github.com/orstsm/notchharbor.git` before tagging this release. The new checker uses the stable repository ID; already-installed older checkers reject redirects and need one manual download after the rename. See [RENAMING.md](RENAMING.md). No release is created merely by renaming the app or repository.

Version 2.11.0 adds Settings → Check for Updates and an optional daily check. Daily checks are off by default. Updates are shown inside Settings; there are no system notifications or automatic installations. Users with 2.10.1 or older must manually install a version with the checker first.

## Publish from GitHub Desktop

Regular commits and pushes do not publish app downloads. The community release workflow runs only when you push a version tag to `orstsm/notchharbor`.

1. Prepare and test the update. Set `CFBundleShortVersionString` in Info.plist to the new version, increment `CFBundleVersion`, and add `RELEASE-NOTES-MAJOR.MINOR.PATCH.md`. Use a version higher than the previous release. Confirm redistribution rights for all included audio/assets.
2. In GitHub Desktop, review and commit all intended changes, including the workflow and packaging script. Use a clear summary such as **Prepare NotchHarbor 2.17.3 community release**. Complete the live Spotify library and overnight sleep/wake acceptance checks before publishing. Push origin.
3. In **History**, right-click that release commit → **Create Tag**, enter the exact version from `Info.plist` (currently `v2.17.3`), then **Push origin**. This tag is the explicit instruction to publish that exact commit.
4. GitHub Actions checks the tag/version and release notes, runs tests, builds Apple Silicon + Intel, verifies the signature and ZIP, and publishes a Release with the community app ZIP, installation instructions and SHA-256 checksums. Allow several minutes; pushing a tag alone does not mean the build succeeded.
5. If needed, **Repository → View on GitHub → Actions** shows progress/errors. Check the Releases page before announcing the download. GitHub may still require website sign-in for troubleshooting or repository settings, but normal release publishing is triggered from Desktop.

No Apple Developer account, personal access token, or signing secret is required for this workflow. It uses GitHub's short-lived built-in token with repository-content write permission to publish the Release; checkout does not retain credentials. GitHub Actions must be enabled and repository/organization policy must permit the workflow. Private repositories can have Actions billing limits and are not supported by the app's public update checker.

**Community downloads are ad-hoc signed, not Developer ID-signed or Apple-notarized.** Release notes always include this warning. macOS may block opening or require explicit per-app approval and renewed Input Monitoring permission. Never disable Gatekeeper. For a future notarized release, use `release.sh` with your own Developer ID credentials instead.

The workflow will not overwrite an existing release. If publishing fails after creating a draft, inspect that draft and its assets on GitHub before retrying; do not move/reuse a published version tag. Build/test failures before publication leave no downloadable release. For a local packaging check without publishing, run `zsh package-community.sh v2.17.3`.

Before committing, run `python3 scripts/security_check.py --history`. It checks working files, staged contents and locally reachable history without printing matching secrets. CI runs the same check with full history before testing and packaging. This is pattern-based detection, not a guarantee; do not commit credentials or exported app preferences. If a real token was committed, revoke/rotate it even if a later commit removes the file.

Builds use a new staging bundle and validate `scripts/bundle-files.txt`. If an intended new asset is rejected, review it and update that allowlist; do not disable the check. The community ZIP is unpacked and verified before it is approved for upload. Local source ZIPs exclude ignored/private files. Workflow actions are pinned to full commit revisions; verify upstream provenance when updating those pins. The source and packaging safeguards do not require reconnecting Spotify or reinstalling the app.

The app checker compares numeric versions, ignores drafts/prereleases, and opens the public release page so users can read notes and choose the ZIP. It does not install updates automatically. A failed workflow does not notify app users of a new version.

Private repositories are not supported by this unauthenticated checker. No tokens are embedded. A 404 means no public release exists or the repository is private; the app explains that rather than saying it is up to date. Network/rate-limit errors show a retry-later message. Daily attempts are limited to approximately once per 24 hours while the app runs, with no catch-up backlog after sleep. Manual checks are limited to one start per 30 seconds. Turning daily checks off cancels future scheduled checks; an already-running check may finish.

GitHub API reference: https://docs.github.com/en/rest/releases/releases#get-the-latest-release
