#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
BUILD_ROOT="$PROJECT_ROOT/.build-talkfloat"
cd "$PROJECT_ROOT"
mkdir -p "$BUILD_ROOT" "$PROJECT_ROOT/dist"
swift build --package-path native --scratch-path "$BUILD_ROOT" --arch arm64 -c release > "$BUILD_ROOT/release.log" 2>&1 || { tail -n 60 "$BUILD_ROOT/release.log"; exit 1; }
BIN_DIR=$(swift build --package-path native --scratch-path "$BUILD_ROOT" --arch arm64 -c release --show-bin-path)
"$BIN_DIR/TalkFloat" --render-brand-icon "$PROJECT_ROOT/native/Resources/AppIcon.png"
APP_PATH="$PROJECT_ROOT/dist/TalkFloat.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_DIR/TalkFloat" "$APP_PATH/Contents/MacOS/TalkFloat"
cp native/Resources/Info.plist "$APP_PATH/Contents/Info.plist"
cp native/Sources/SpeexDSP/COPYING "$APP_PATH/Contents/Resources/SpeexDSP-LICENSE.txt"
ICONSET="$BUILD_ROOT/AppIcon.iconset"
mkdir -p "$ICONSET"
for dimension in 16 32 128 256 512; do
    sips -z "$dimension" "$dimension" native/Resources/AppIcon.png --out "$ICONSET/icon_${dimension}x${dimension}.png" >/dev/null
    doubled=$((dimension * 2))
    sips -z "$doubled" "$doubled" native/Resources/AppIcon.png --out "$ICONSET/icon_${dimension}x${dimension}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP_PATH/Contents/Resources/AppIcon.icns"
IDENTITY="${TALKFLOAT_SIGN_IDENTITY:-${SAYLORI_SIGN_IDENTITY:-}}"
if [[ -z "${TALKFLOAT_SIGN_IDENTITY+x}" && -z "${SAYLORI_SIGN_IDENTITY+x}" ]]; then
    FOUND_IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*) \([A-F0-9]\{40\}\) "Apple Development:.*/\1/p' | head -1)
    if [[ -n "$FOUND_IDENTITY" ]]; then IDENTITY="$FOUND_IDENTITY"; fi
fi
if [[ -z "$IDENTITY" ]]; then
    echo "No stable Apple Development signing identity found. Configure TALKFLOAT_SIGN_IDENTITY; do not silently change the app's permission identity." >&2
    exit 1
fi
codesign --force --options runtime --sign "$IDENTITY" --entitlements native/Resources/TalkFloat.entitlements "$APP_PATH"
codesign --verify --strict "$APP_PATH"
APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")
ditto -c -k --keepParent "$APP_PATH" "$PROJECT_ROOT/dist/TalkFloat-$APP_VERSION-macOS-arm64.zip"
echo "$APP_PATH"
