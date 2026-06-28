#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Agent Drop.app"
DMG_NAME="AgentDrop-developer.dmg"
VOLUME_NAME="Agent Drop"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$DIST_DIR/dmg-staging"
DMG_PATH="$DIST_DIR/$DMG_NAME"
MOUNT_POINT="$DIST_DIR/dmg-mounted"

usage() {
    cat <<EOF
Usage: $0 [path/to/AgentDrop.app]

Builds a developer DMG containing:
- Agent Drop.app
- Applications shortcut

If no app path is provided, the script uses the newest Debug AgentDrop.app from Xcode DerivedData.
EOF
}

find_default_app() {
    /usr/bin/find "$HOME/Library/Developer/Xcode/DerivedData" \
        -path "*/AgentDrop-*/Build/Products/Debug/AgentDrop.app" \
        -type d \
        -not -path "*/Index.noindex/*" \
        | /usr/bin/sort \
        | /usr/bin/tail -n 1
}

APP_SRC="${1:-}"
if [[ "${APP_SRC:-}" == "-h" || "${APP_SRC:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ -z "$APP_SRC" ]]; then
    APP_SRC="$(find_default_app)"
fi

if [[ -z "$APP_SRC" || ! -d "$APP_SRC" ]]; then
    echo "error: AgentDrop.app not found. Build the app first or pass an app path." >&2
    exit 1
fi

if [[ "$(basename "$APP_SRC")" != "AgentDrop.app" && "$(basename "$APP_SRC")" != "$APP_NAME" ]]; then
    echo "error: expected an AgentDrop.app bundle, got: $APP_SRC" >&2
    exit 1
fi

cleanup_mount() {
    if /sbin/mount | /usr/bin/grep -q "on $MOUNT_POINT "; then
        /usr/bin/hdiutil detach "$MOUNT_POINT" >/dev/null || true
    fi
    /bin/rm -rf "$MOUNT_POINT"
}

trap cleanup_mount EXIT

/bin/rm -rf "$STAGING_DIR" "$DMG_PATH" "$MOUNT_POINT"
/bin/mkdir -p "$STAGING_DIR" "$DIST_DIR"

/usr/bin/ditto "$APP_SRC" "$STAGING_DIR/$APP_NAME"
/bin/ln -s /Applications "$STAGING_DIR/Applications"

/usr/bin/hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

/bin/mkdir -p "$MOUNT_POINT"
/usr/bin/hdiutil attach "$DMG_PATH" -nobrowse -mountpoint "$MOUNT_POINT" >/dev/null
test -d "$MOUNT_POINT/$APP_NAME"
test -L "$MOUNT_POINT/Applications"

/usr/bin/hdiutil detach "$MOUNT_POINT" >/dev/null
/bin/rm -rf "$STAGING_DIR"

echo "$DMG_PATH"
