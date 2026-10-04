#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$PROJECT_DIR/.build/Products/NotchHarbor.app"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$PROJECT_DIR/Info.plist")"
UPLOAD_ZIP="$DIST_DIR/NotchHarbor-notarization.zip"
FINAL_ZIP="$DIST_DIR/NotchHarbor-$VERSION.zip"

: "${MECHAKEYS_SIGNING_IDENTITY:?Set this to your Developer ID Application identity}"
: "${MECHAKEYS_NOTARY_PROFILE:?Set this to your notarytool keychain profile}"

[[ "$MECHAKEYS_SIGNING_IDENTITY" != "-" ]] || { echo "Developer ID required" >&2; exit 1; }
python3 "$PROJECT_DIR/scripts/security_check.py" --history
MECHAKEYS_SIGNING_IDENTITY="$MECHAKEYS_SIGNING_IDENTITY" "$PROJECT_DIR/build.sh" --build-only

mkdir -p "$DIST_DIR"
rm -f "$UPLOAD_ZIP" "$FINAL_ZIP"
ditto -c -k --keepParent "$APP_DIR" "$UPLOAD_ZIP"

xcrun notarytool submit "$UPLOAD_ZIP" \
    --keychain-profile "$MECHAKEYS_NOTARY_PROFILE" \
    --wait

xcrun stapler staple "$APP_DIR"
xcrun stapler validate "$APP_DIR"
spctl --assess --type execute --verbose=2 "$APP_DIR"
python3 "$PROJECT_DIR/scripts/verify_bundle.py" "$APP_DIR"

ditto -c -k --keepParent "$APP_DIR" "$FINAL_ZIP"
rm -f "$UPLOAD_ZIP"

echo "Created notarized release: $FINAL_ZIP"
