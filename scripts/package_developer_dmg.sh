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
    local derived_data="$HOME/Library/Developer/Xcode/DerivedData"
    if [[ ! -d "$derived_data" ]]; then
        return 0
    fi

    /usr/bin/find "$derived_data" \
        -path "*/AgentDrop-*/Build/Products/Debug/AgentDrop.app" \
        -type d \
        -not -path "*/Index.noindex/*" \
        -print0 \
        | while IFS= read -r -d '' app_path; do
            printf '%s\t%s\n' "$(/usr/bin/stat -f '%m' "$app_path")" "$app_path"
        done \
        | /usr/bin/sort -n \
        | /usr/bin/tail -n 1 \
        | /usr/bin/cut -f2-
}

cleanup() {
    if /sbin/mount | /usr/bin/grep -Fq " on $MOUNT_POINT "; then
        /usr/bin/hdiutil detach "$MOUNT_POINT" >/dev/null || true
    fi
    /bin/rm -rf "$STAGING_DIR" "$MOUNT_POINT"
}

package_developer_dmg() {
    local app_src="$1"

    if [[ -z "$app_src" || ! -d "$app_src" ]]; then
        echo "error: AgentDrop.app not found. Build the app first or pass an app path." >&2
        exit 1
    fi

    if [[ "$(basename "$app_src")" != "AgentDrop.app" && "$(basename "$app_src")" != "$APP_NAME" ]]; then
        echo "error: expected an AgentDrop.app bundle, got: $app_src" >&2
        exit 1
    fi

    trap cleanup EXIT

    /bin/rm -rf "$STAGING_DIR" "$DMG_PATH" "$MOUNT_POINT"
    /bin/mkdir -p "$STAGING_DIR" "$DIST_DIR"

    /usr/bin/ditto "$app_src" "$STAGING_DIR/$APP_NAME"
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
}

main() {
    local app_src="${1:-}"
    if [[ "${app_src:-}" == "-h" || "${app_src:-}" == "--help" ]]; then
        usage
        exit 0
    fi

    if [[ -z "$app_src" ]]; then
        app_src="$(find_default_app)"
    fi

    package_developer_dmg "$app_src"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
