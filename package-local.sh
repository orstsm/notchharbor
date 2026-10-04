#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
BUILD_DIR="$PROJECT_DIR/.build"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$BUILD_DIR/Products/NotchHarbor.app"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$PROJECT_DIR/Info.plist")"
DMG_PATH="$DIST_DIR/NotchHarbor-$VERSION-universal-local.dmg"
APP_ZIP="$DIST_DIR/NotchHarbor-$VERSION-universal-personal.zip"
SOURCE_ZIP="$DIST_DIR/NotchHarbor-$VERSION-github-source.zip"

"$PROJECT_DIR/build.sh" --build-only

mkdir -p "$DIST_DIR"
DMG_STAGE="$(mktemp -d "$BUILD_DIR/dmg-stage.XXXXXX")"
SOURCE_STAGE="$(mktemp -d "$BUILD_DIR/source-stage.XXXXXX")"
trap 'rm -rf -- "$DMG_STAGE" "$SOURCE_STAGE"' EXIT

ditto "$APP_DIR" "$DMG_STAGE/NotchHarbor.app"
ln -s /Applications "$DMG_STAGE/Applications"
cp "$PROJECT_DIR/INSTALL.md" "$DMG_STAGE/Read Me First.md"

ditto -c -k --keepParent --norsrc --noextattr "$APP_DIR" "$APP_ZIP"

if hdiutil create \
    -volname "NotchHarbor $VERSION" \
    -srcfolder "$DMG_STAGE" \
    -format UDZO \
    -ov \
    "$DMG_PATH"; then
    echo "Created personal DMG installer: $DMG_PATH"
else
    echo "DMG creation is unavailable in this environment; use the universal app ZIP."
fi

SOURCE_ROOT="$SOURCE_STAGE/NotchHarbor"
python3 "$PROJECT_DIR/scripts/stage_source.py" "$SOURCE_ROOT"

ditto -c -k --keepParent --norsrc --noextattr "$SOURCE_ROOT" "$SOURCE_ZIP"

echo "Created universal app archive: $APP_ZIP"
echo "Created GitHub source archive: $SOURCE_ZIP"
