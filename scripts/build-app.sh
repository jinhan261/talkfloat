#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
BUILD_ROOT="$PROJECT_ROOT/.build-talkfloat"
cd "$PROJECT_ROOT"
# Local ad-hoc builds are explicit; never silently replace a stable identity.
MODE="${1:-}"
if [[ $# -gt 1 || ( -n "$MODE" && "$MODE" != "--ad-hoc" ) ]]; then
    echo "Usage: scripts/build-app.sh [--ad-hoc]" >&2; exit 2
fi
IDENTITY="${TALKFLOAT_SIGN_IDENTITY:-${SAYLORI_SIGN_IDENTITY:-}}"
if [[ "$MODE" == "--ad-hoc" ]]; then
    IDENTITY="-"
    echo "Local ad-hoc build: updates may require new audio/Keychain authorization." >&2
elif [[ -z "$IDENTITY" ]]; then
    IDENTITIES=("${(@f)$(security find-identity -v -p codesigning | sed -n 's/.*) \([A-F0-9]\{40\}\) "Apple Development:.*/\1/p')}")
    if [[ ${#IDENTITIES[@]} -eq 1 && -n "${IDENTITIES[1]}" ]]; then
        IDENTITY="${IDENTITIES[1]}"
    else
        echo "Set TALKFLOAT_SIGN_IDENTITY to a stable signing identity, or explicitly use --ad-hoc for a local source build." >&2
        exit 1
    fi
fi
mkdir -p "$BUILD_ROOT" "$PROJECT_ROOT/dist"
swift build --package-path native --scratch-path "$BUILD_ROOT" --arch arm64 -c release > "$BUILD_ROOT/release.log" 2>&1 || { tail -n 60 "$BUILD_ROOT/release.log"; exit 1; }
BIN_DIR=$(swift build --package-path native --scratch-path "$BUILD_ROOT" --arch arm64 -c release --show-bin-path)
# The app now links Sparkle. Render from the assembled bundle after its
# framework has been embedded, not from a bare SwiftPM executable.
APP_PATH="$PROJECT_ROOT/dist/Build.noindex/TalkFloat.app"
STAGING=$(mktemp -d "$BUILD_ROOT/app-stage.XXXXXX")
cleanup() {
    if [[ -d "$STAGING" && ! -L "$STAGING" && "${STAGING:A:h}" == "$BUILD_ROOT" && "${STAGING:t}" == app-stage.* ]]; then
        rm -rf -- "$STAGING"
    fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
FINAL_APP_PATH="$APP_PATH"
APP_PATH="$STAGING/TalkFloat.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_DIR/TalkFloat" "$APP_PATH/Contents/MacOS/TalkFloat"
cp native/Resources/Info.plist "$APP_PATH/Contents/Info.plist"
cp LICENSE "$APP_PATH/Contents/Resources/TalkFloat-LICENSE.txt"
cp native/Sources/SpeexDSP/COPYING "$APP_PATH/Contents/Resources/SpeexDSP-LICENSE.txt"
cp native/Tests/Fixtures/english-meeting-v2.aiff "$APP_PATH/Contents/Resources/EnglishSample.aiff"
SPARKLE_ROOT="$BUILD_ROOT/artifacts/sparkle/Sparkle"
SPARKLE_FRAMEWORK="$SPARKLE_ROOT/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
mkdir -p "$APP_PATH/Contents/Frameworks"
ditto "$SPARKLE_FRAMEWORK" "$APP_PATH/Contents/Frameworks/Sparkle.framework"
if [[ -f "$SPARKLE_ROOT/LICENSE" ]]; then cp "$SPARKLE_ROOT/LICENSE" "$APP_PATH/Contents/Resources/Sparkle-LICENSE.txt"; fi
ICONSET="$BUILD_ROOT/AppIcon.iconset"
mkdir -p "$ICONSET"
for dimension in 16 32 128 256 512; do
    sips -z "$dimension" "$dimension" native/Resources/AppIcon.png --out "$ICONSET/icon_${dimension}x${dimension}.png" >/dev/null
    doubled=$((dimension * 2))
    sips -z "$doubled" "$doubled" native/Resources/AppIcon.png --out "$ICONSET/icon_${dimension}x${dimension}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP_PATH/Contents/Resources/AppIcon.icns"
SIGN_OPTIONS=(--force)
if [[ "$IDENTITY" != "-" ]]; then SIGN_OPTIONS+=(--options runtime --timestamp); fi
FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B"
# Sign executable leaves before their enclosing bundles, preserving Sparkle's
# helper entitlements. Never use --deep as a substitute for inside-out signing.
for component in "$FRAMEWORK/Autoupdate" "$FRAMEWORK/Updater.app" "$FRAMEWORK/XPCServices/Downloader.xpc" "$FRAMEWORK/XPCServices/Installer.xpc"; do
    if [[ -e "$component" ]]; then codesign "${SIGN_OPTIONS[@]}" --preserve-metadata=entitlements --sign "$IDENTITY" "$component"; fi
done
codesign "${SIGN_OPTIONS[@]}" --sign "$IDENTITY" "$APP_PATH/Contents/Frameworks/Sparkle.framework"
codesign "${SIGN_OPTIONS[@]}" --sign "$IDENTITY" --entitlements native/Resources/TalkFloat.entitlements "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")
ditto -c -k --keepParent "$APP_PATH" "$STAGING/TalkFloat.zip"
mkdir -p "${FINAL_APP_PATH:h}"
# Retire only this exact build output after the fresh bundle has passed signing.
if [[ -d "$FINAL_APP_PATH" ]]; then mv "$FINAL_APP_PATH" "$STAGING/previous.app"; fi
if ! mv "$APP_PATH" "$FINAL_APP_PATH"; then
    if [[ -d "$STAGING/previous.app" ]]; then mv "$STAGING/previous.app" "$FINAL_APP_PATH"; fi
    exit 1
fi
mv "$STAGING/TalkFloat.zip" "$PROJECT_ROOT/dist/TalkFloat-$APP_VERSION-macOS-arm64.zip"
APP_PATH="$FINAL_APP_PATH"
echo "$APP_PATH"
