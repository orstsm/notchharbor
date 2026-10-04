#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h}"
cd "$PROJECT_DIR"
VERSION="$(plutil -extract CFBundleShortVersionString raw Info.plist)"
TAG="${1:-}"
if ! printf '%s\n' "$TAG" | /usr/bin/grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || [[ "$TAG" != "v$VERSION" ]]; then
    echo "Release tag must be v$VERSION, matching Info.plist." >&2
    exit 1
fi
NOTES="RELEASE-NOTES-$VERSION.md"
if [[ ! -s "$NOTES" ]]; then
    echo "Missing release notes: $NOTES" >&2
    exit 1
fi
if [[ "${2:-}" == "--validate-only" ]]; then
    echo "Release metadata valid: $TAG"
    exit 0
fi
# Community packages never depend on a developer certificate or local identity.
python3 scripts/security_check.py --history
MECHAKEYS_SIGNING_IDENTITY=- zsh build.sh --build-only
APP_DIR="$PROJECT_DIR/.build/Products/NotchHarbor.app"
codesign --verify --deep --strict "$APP_DIR"
xcrun lipo "$APP_DIR/Contents/MacOS/NotchHarbor" -verify_arch arm64
xcrun lipo "$APP_DIR/Contents/MacOS/NotchHarbor" -verify_arch x86_64
mkdir -p dist
ARCHIVE="NotchHarbor-$VERSION-universal-community.zip"
ditto -c -k --keepParent --norsrc --noextattr "$APP_DIR" "dist/$ARCHIVE"
unzip -tq "dist/$ARCHIVE"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/mechakeys-release-check.XXXXXX")"
trap 'rm -rf -- "$STAGE"' EXIT
ditto -x -k "dist/$ARCHIVE" "$STAGE"
codesign --verify --deep --strict "$STAGE/NotchHarbor.app"
python3 scripts/verify_bundle.py "$STAGE/NotchHarbor.app"
cp INSTALL.md dist/INSTALL.md
{
    printf '%s\n\n' '**Community build: ad-hoc signed, NOT notarized by Apple.** macOS may block opening or require per-app approval. Never disable system-wide security protections.'
    cat "$NOTES"
} > dist/community-release-notes.md
(cd dist && shasum -a 256 "$ARCHIVE" INSTALL.md > SHA256SUMS.txt)
echo "Verified community package: dist/$ARCHIVE"
