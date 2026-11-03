#!/bin/zsh
# Build reviewed local sources; never download or execute a remote install script.
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
if pgrep -x TalkFloat >/dev/null || pgrep -x Saylori >/dev/null; then
    echo "Quit TalkFloat before installing so the current meeting can finish saving." >&2
    exit 1
fi
DESTINATION="$HOME/Applications/TalkFloat.app"
if [[ "${1:-}" == "--ad-hoc" && -d "$DESTINATION" ]]; then
    SIGNATURE_DETAILS=$(codesign -dvv "$DESTINATION" 2>&1 || true)
    if [[ "$SIGNATURE_DETAILS" == *"Authority="* ]]; then
        echo "Existing installation has a certificate identity. Keep that identity via TALKFLOAT_SIGN_IDENTITY; refusing to replace it with ad-hoc signing." >&2
        exit 1
    fi
fi
"$PROJECT_ROOT/scripts/build-app.sh" "$@"
mkdir -p "$HOME/Applications"
STAGING=$(mktemp -d "$HOME/Applications/.talkfloat-install.XXXXXX")
cleanup() {
    if [[ -d "$STAGING/previous.app" && ! -e "$DESTINATION" ]]; then
        mv "$STAGING/previous.app" "$DESTINATION" || return
    fi
    if [[ -d "$STAGING" && ! -L "$STAGING" && "${STAGING:A:h}" == "${DESTINATION:A:h}" && "${STAGING:t}" == .talkfloat-install.* ]]; then
        rm -rf -- "$STAGING"
    fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
ditto "$PROJECT_ROOT/dist/Build.noindex/TalkFloat.app" "$STAGING/TalkFloat.app"
codesign --verify --strict "$STAGING/TalkFloat.app"
if [[ -e "$DESTINATION" ]]; then
    BACKUP="$PROJECT_ROOT/dist/previous/TalkFloat-$(date +%Y%m%d-%H%M%S)-${STAGING:t}.zip"
    mkdir -p "${BACKUP:h}"
    ditto -c -k --keepParent "$DESTINATION" "$BACKUP"
    unzip -tq "$BACKUP" >/dev/null
    mv "$DESTINATION" "$STAGING/previous.app"
fi
if ! mv "$STAGING/TalkFloat.app" "$DESTINATION"; then
    if [[ -d "$STAGING/previous.app" ]]; then mv "$STAGING/previous.app" "$DESTINATION"; fi
    echo "Installation failed; the previous installation was restored." >&2
    exit 1
fi
if [[ -d "$STAGING/previous.app" ]]; then rm -rf -- "$STAGING/previous.app"; fi
if [[ "${TALKFLOAT_NO_OPEN:-0}" != "1" ]]; then open "$DESTINATION"; fi
echo "Installed: $DESTINATION"
