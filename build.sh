#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
BUILD_DIR="$PROJECT_DIR/.build"
python3 "$PROJECT_DIR/scripts/security_check.py"
mkdir -p "$BUILD_DIR/Products"
# Only a freshly created staging directory is packaged. An old build remains
# intact until the new bundle has passed all checks; installed apps are untouched.
BUILD_STAGE="$(mktemp -d "$BUILD_DIR/release-stage.XXXXXX")"
trap 'rm -rf -- "$BUILD_STAGE"' EXIT
APP_DIR="$BUILD_STAGE/NotchHarbor.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MODULE_CACHE_DIR="$BUILD_DIR/module-cache"
ARCHS=(arm64 x86_64)

# Prefer the stable SDK when a newer Command Line Tools compiler is installed
# alongside a prerelease SDK with a different Swift patch version.
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
if [[ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk" ]]; then
    SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
elif [[ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk" ]]; then
    SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
fi

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$MODULE_CACHE_DIR"
cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/PrivacyInfo.xcprivacy" "$RESOURCES_DIR/PrivacyInfo.xcprivacy"
cp "$PROJECT_DIR/Resources/AppIcon.png" "$RESOURCES_DIR/AppIcon.png"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
cp -R "$PROJECT_DIR/Resources/Sounds" "$RESOURCES_DIR/Sounds"

for arch in "${ARCHS[@]}"; do
    ARCH_BUILD_DIR="$BUILD_DIR/$arch"
    ARCH_MODULE_CACHE_DIR="$MODULE_CACHE_DIR/$arch"
    mkdir -p "$ARCH_BUILD_DIR" "$ARCH_MODULE_CACHE_DIR"

    xcrun clang -fobjc-arc -fmodules -isysroot "$SDK_PATH" \
        -fmodules-cache-path="$ARCH_MODULE_CACHE_DIR" \
        -target "$arch-apple-macos13.0" -c "$PROJECT_DIR/Sources/AudioSafety.m" \
        -o "$ARCH_BUILD_DIR/AudioSafety.o"

    xcrun swiftc \
        -parse-as-library \
        -O \
        -sdk "$SDK_PATH" \
        -module-cache-path "$ARCH_MODULE_CACHE_DIR" \
        -target "$arch-apple-macos13.0" \
        -framework AppKit \
        -framework ApplicationServices \
        -framework AVFoundation \
        -framework Combine \
        -framework CoreAudio \
        -framework CoreGraphics \
        -framework QuartzCore \
        -framework ServiceManagement \
        -framework SwiftUI \
        -import-objc-header "$PROJECT_DIR/Sources/AudioSafety.h" \
        "$ARCH_BUILD_DIR/AudioSafety.o" \
        "$PROJECT_DIR"/Sources/*.swift \
        -o "$ARCH_BUILD_DIR/NotchHarbor"
done

xcrun lipo -create \
    "$BUILD_DIR/arm64/NotchHarbor" \
    "$BUILD_DIR/x86_64/NotchHarbor" \
    -output "$MACOS_DIR/NotchHarbor"

SIGNING_IDENTITY="${MECHAKEYS_SIGNING_IDENTITY:--}"
python3 "$PROJECT_DIR/scripts/verify_bundle.py" "$APP_DIR" --unsigned

# Files copied from development tools can carry provenance metadata that makes
# Launch Services reject an otherwise valid local bundle. Strip it before the
# final signature so Finder and Spotlight can open and index the app normally.
xattr -cr "$APP_DIR"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    echo "Warning: ad-hoc community build, NOT notarized by Apple. Disclose this when sharing."
    codesign \
        --force \
        --deep \
        --options runtime \
        --entitlements "$PROJECT_DIR/NotchHarbor.entitlements" \
        --sign - \
        "$APP_DIR"
else
    codesign \
        --force \
        --deep \
        --options runtime \
        --entitlements "$PROJECT_DIR/NotchHarbor.entitlements" \
        --timestamp \
        --sign "$SIGNING_IDENTITY" \
        "$APP_DIR"
fi

plutil -lint "$CONTENTS_DIR/Info.plist" "$RESOURCES_DIR/PrivacyInfo.xcprivacy"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
xcrun lipo -info "$MACOS_DIR/NotchHarbor"
python3 "$PROJECT_DIR/scripts/verify_bundle.py" "$APP_DIR"

FINAL_APP="$BUILD_DIR/Products/NotchHarbor.app"
if [[ -L "$FINAL_APP" ]]; then
    echo "Refusing to replace a symbolic-link build product." >&2
    exit 1
fi
if [[ -e "$FINAL_APP" ]]; then
    mv "$FINAL_APP" "$BUILD_STAGE/previous.bundle-backup"
fi
if ! mv "$APP_DIR" "$FINAL_APP"; then
    [[ ! -e "$BUILD_STAGE/previous.bundle-backup" ]] || mv "$BUILD_STAGE/previous.bundle-backup" "$FINAL_APP"
    exit 1
fi

echo "Built $FINAL_APP"
echo "Builds never replace the installed app. Quit NotchHarbor, then run: zsh install.sh"
