#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mechakeys-tests.XXXXXX")"
trap 'rm -rf -- "$TEST_DIR"' EXIT
cd "$PROJECT_DIR"
PYTHONDONTWRITEBYTECODE=1 python3 Tests/SecurityGuardTests.py
python3 scripts/security_check.py
xcrun clang -fobjc-arc -fmodules -fmodules-cache-path="$TEST_DIR/cache" -c Sources/AudioSafety.m -o "$TEST_DIR/AudioSafety.o"
xcrun swiftc -module-cache-path "$TEST_DIR/cache" Sources/HarborPreferences.swift Sources/ShelfModel.swift Tests/HoverStateTests.swift -o "$TEST_DIR/hover"
"$TEST_DIR/hover"
xcrun swiftc -module-cache-path "$TEST_DIR/cache" Sources/HarborPreferences.swift Sources/PreviewActivation.swift Sources/ShelfModel.swift Sources/SpotifyArtwork.swift Sources/SpotifyLocalOutputMonitor.swift Sources/SpotifyController.swift Tests/HarborTests.swift -o "$TEST_DIR/harbor"
"$TEST_DIR/harbor"
xcrun swiftc -module-cache-path "$TEST_DIR/cache" Sources/SpotifyArtwork.swift Sources/SpotifyLocalOutputMonitor.swift Sources/SpotifyController.swift Sources/SpotifyLibrary.swift Tests/SpotifyLibraryTests.swift -o "$TEST_DIR/spotify-library"
"$TEST_DIR/spotify-library"
xcrun swiftc -module-cache-path "$TEST_DIR/cache" Sources/SpotifyLocalOutputMonitor.swift Tests/SpotifyLocalOutputTests.swift -o "$TEST_DIR/spotify-output"
"$TEST_DIR/spotify-output"
xcrun swiftc -module-cache-path "$TEST_DIR/cache" Sources/WorkspaceLifecycleMonitor.swift Tests/WorkspaceLifecycleTests.swift -o "$TEST_DIR/workspace-lifecycle"
"$TEST_DIR/workspace-lifecycle"
xcrun swiftc -module-cache-path "$TEST_DIR/cache" -import-objc-header Sources/AudioSafety.h "$TEST_DIR/AudioSafety.o" Sources/GlobalKeyboardMonitor.swift Sources/CustomSoundPack.swift Sources/KeyboardAudioEngine.swift Sources/InputAudioController.swift Tests/AudioLifecycleTests.swift -o "$TEST_DIR/audio"
"$TEST_DIR/audio"
xcrun swiftc -module-cache-path "$TEST_DIR/cache" Sources/GlobalKeyboardMonitor.swift Tests/InputMonitorTests.swift -o "$TEST_DIR/input-monitor"
"$TEST_DIR/input-monitor"
xcrun swiftc -module-cache-path "$TEST_DIR/cache" Sources/CustomSoundPack.swift Tests/CustomSoundPackTests.swift -o "$TEST_DIR/custom-packs"
"$TEST_DIR/custom-packs"
xcrun swiftc -module-cache-path "$TEST_DIR/cache" -import-objc-header Sources/AudioSafety.h "$TEST_DIR/AudioSafety.o" Sources/CustomSoundPack.swift Sources/KeyboardAudioEngine.swift Tests/BundledAudioTests.swift -o "$TEST_DIR/bundled-audio"
"$TEST_DIR/bundled-audio" "$PROJECT_DIR/Resources"
xcrun swiftc -module-cache-path "$TEST_DIR/cache" Sources/UpdateChecker.swift Tests/UpdateTests.swift -o "$TEST_DIR/updates"
"$TEST_DIR/updates"
xcrun swiftc -typecheck -module-cache-path "$TEST_DIR/cache" Tests/InstallApp.swift
zsh -n build.sh install.sh package-local.sh package-community.sh release.sh Tests/install-migration.sh
VERSION="$(plutil -extract CFBundleShortVersionString raw Info.plist)"
zsh package-community.sh "v$VERSION" --validate-only
for INVALID_TAG in v0.0.0 v2.12.0-beta invalid; do
    if zsh package-community.sh "$INVALID_TAG" --validate-only; then
        echo "Invalid release tag was accepted: $INVALID_TAG" >&2
        exit 1
    fi
done
plutil -lint Info.plist PrivacyInfo.xcprivacy NotchHarbor.entitlements
for PACK in holy-panda mx-blue mx-brown nk-cream typewriter; do
    PACK_DIR="Resources/Sounds/Community/$PACK"
    [[ -d "$PACK_DIR" ]] || { echo "Missing bundled sound profile: $PACK" >&2; exit 1; }
    find "$PACK_DIR" -maxdepth 1 -type f \( -iname '*.wav' -o -iname '*.mp3' \) | /usr/bin/grep -q . || {
        echo "Bundled sound profile has no audio: $PACK" >&2
        exit 1
    }
done
