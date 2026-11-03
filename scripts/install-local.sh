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
trap 'rmdir "$STAGING" 2>/dev/null || true' EXIT
ditto "$PROJECT_ROOT/dist/TalkFloat.app" "$STAGING/TalkFloat.app"
codesign --verify --strict "$STAGING/TalkFloat.app"
if [[ -e "$DESTINATION" ]]; then
    BACKUP="$PROJECT_ROOT/dist/previous/TalkFloat-$(date +%Y%m%d-%H%M%S).app.backup"
    mkdir -p "${BACKUP:h}"
    mv "$DESTINATION" "$BACKUP"
fi
mv "$STAGING/TalkFloat.app" "$DESTINATION"
if [[ "${TALKFLOAT_NO_OPEN:-0}" != "1" ]]; then open "$DESTINATION"; fi
echo "Installed: $DESTINATION"
