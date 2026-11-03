#!/bin/zsh
# Package the already-built app; never replace or re-sign an installed app.
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
APP_PATH="${TALKFLOAT_APP_PATH:-$PROJECT_ROOT/dist/Build.noindex/TalkFloat.app}"
APP_PATH="${APP_PATH:A}"
MODE="${1:-}"
if [[ $# -ne 1 || ( "$MODE" != "--development" && "$MODE" != "--release" ) ]]; then
    echo "Usage: scripts/package-dmg.sh --development | --release" >&2
    echo "Release mode requires a Developer ID app, TALKFLOAT_SIGN_IDENTITY and TALKFLOAT_NOTARY_PROFILE." >&2
    exit 2
fi
if [[ ! -d "$APP_PATH" ]]; then
    echo "Run scripts/build-app.sh first, or set TALKFLOAT_APP_PATH to a signed app copy." >&2; exit 1
fi
codesign --verify --deep --strict "$APP_PATH"
APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")
if [[ ! "$APP_VERSION" =~ '^[0-9]+([.][0-9]+)*$' ]]; then
    echo "Unexpected app version; refusing to construct an output filename." >&2; exit 1
fi
if [[ "$(lipo -archs "$APP_PATH/Contents/MacOS/TalkFloat")" != "arm64" ]]; then
    echo "This packaging target is for the current Apple Silicon build only." >&2; exit 1
fi

SUFFIX="-development"
if [[ "$MODE" == "--release" ]]; then
    SIGNATURE_DETAILS=$(codesign -dvv "$APP_PATH" 2>&1)
    if [[ "$SIGNATURE_DETAILS" != *"Authority=Developer ID Application:"* ]]; then
        echo "Release requires a Developer ID Application signature. Apple Development is not a distribution identity." >&2
        exit 1
    fi
    : "${TALKFLOAT_SIGN_IDENTITY:?Set a Developer ID Application signing identity}"
    : "${TALKFLOAT_NOTARY_PROFILE:?Set the name of an existing notarytool Keychain profile}"
    SUFFIX=""
fi
OUTPUT="$PROJECT_ROOT/dist/TalkFloat-$APP_VERSION-macOS-arm64$SUFFIX.dmg"
if [[ -e "$OUTPUT" || -e "$OUTPUT.sha256" ]]; then
    echo "Output already exists; preserve it or move it before packaging again: $OUTPUT" >&2; exit 1
fi

STAGING=$(mktemp -d "$PROJECT_ROOT/dist/.dmg-stage.XXXXXX")
cleanup() {
    # STAGING comes only from mktemp under this project's dist directory.
    if [[ -d "$STAGING" && ! -L "$STAGING" && "${STAGING:A:h}" == "$PROJECT_ROOT/dist" && "${STAGING:t}" == .dmg-stage.* ]]; then
        rm -rf -- "$STAGING"
    fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
mkdir "$STAGING/volume"
ditto "$APP_PATH" "$STAGING/volume/TalkFloat.app"
ln -s /Applications "$STAGING/volume/Applications"
cat > "$STAGING/volume/安装说明.txt" <<'TEXT'
TalkFloat · 英语实时中文字幕

1. 将 TalkFloat.app 拖到 Applications 文件夹。
2. 从 Applications 打开 TalkFloat；它出现在右上角菜单栏，没有主窗口。
3. 选择本地模型并按提示准备语言资源；也可配置自己的豆包凭据。
4. 首次收听时按 macOS 提示授予系统声音权限，需要麦克风时单独开启。

Apple Silicon Mac。本地模型要求 macOS 26.4 或更新版本。
升级前结束并存档当前会议，然后退出旧版。已安装到其他位置时，替换原位置，避免保留两份 App。
只保存中英文字，不保存录音；没有附带任何人的 Token、模型或会议记录。

项目与支持：https://github.com/jinhan261/talkfloat
TEXT
if [[ "$MODE" == "--development" ]]; then
    cat >> "$STAGING/volume/安装说明.txt" <<'TEXT'

【开发预览包】此包没有经过 Developer ID 分发签名和 Apple 公证。
这是打包验收产物，不是面向普通用户的正式安装包；其他 Mac 可能拒绝打开。
请等待公证版本，不要关闭 Gatekeeper、SIP 或移除 quarantine 来安装。
TEXT
fi
codesign --verify --deep --strict "$STAGING/volume/TalkFloat.app"
hdiutil create -volname "TalkFloat $APP_VERSION" -srcfolder "$STAGING/volume" \
    -format UDZO -fs HFS+ "$STAGING/TalkFloat.dmg"
hdiutil verify "$STAGING/TalkFloat.dmg"

if [[ "$MODE" == "--release" ]]; then
    codesign --force --timestamp --sign "$TALKFLOAT_SIGN_IDENTITY" "$STAGING/TalkFloat.dmg"
    DMG_SIGNATURE=$(codesign -dvv "$STAGING/TalkFloat.dmg" 2>&1)
    if [[ "$DMG_SIGNATURE" != *"Authority=Developer ID Application:"* ]]; then
        echo "The DMG signing identity must also be Developer ID Application." >&2; exit 1
    fi
    # Credentials remain in Keychain; no account password or API key is accepted here.
    NOTARY_LOG="$PROJECT_ROOT/dist/TalkFloat-$APP_VERSION-notarization-$(date +%Y%m%d-%H%M%S).json"
    xcrun notarytool submit "$STAGING/TalkFloat.dmg" \
        --keychain-profile "$TALKFLOAT_NOTARY_PROFILE" --wait --output-format json > "$NOTARY_LOG"
    NOTARY_STATUS=$(/usr/bin/plutil -extract status raw "$NOTARY_LOG")
    if [[ "$NOTARY_STATUS" != "Accepted" ]]; then
        echo "Notarization did not succeed; inspect $NOTARY_LOG before publishing." >&2; exit 1
    fi
    xcrun stapler staple "$STAGING/TalkFloat.dmg"
    xcrun stapler validate "$STAGING/TalkFloat.dmg"
    codesign --verify --strict "$STAGING/TalkFloat.dmg"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$STAGING/TalkFloat.dmg"
fi
mv "$STAGING/TalkFloat.dmg" "$OUTPUT"
(
    cd "${OUTPUT:h}"
    shasum -a 256 "${OUTPUT:t}" > "${OUTPUT:t}.sha256"
)
echo "Created: $OUTPUT"
if [[ "$MODE" == "--development" ]]; then
    echo "Development packaging verified; not notarized or cleared for public installation."
else
    echo "Notarized DMG created; verify first installation on a clean Mac before publishing."
fi
