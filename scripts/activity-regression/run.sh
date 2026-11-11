#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"
swift build --target AgentDropCore
BUILD_DIR="$(swift build --show-bin-path)"
FIXTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp/}agent-drop-activity.XXXXXX")"
APP_DIR="$FIXTURE_DIR/Activity Regression.app"
mkdir -p "$APP_DIR/Contents/MacOS"
swiftc -parse-as-library -swift-version 6 -I "$BUILD_DIR/Modules" \
    scripts/activity-regression/Harness.swift Sources/AgentDropApp/TransferActivityView.swift \
    "$BUILD_DIR"/AgentDropCore.build/*.swift.o -o "$APP_DIR/Contents/MacOS/ActivityRegression"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ActivityRegression</string>
<key>CFBundleIdentifier</key><string>ai.shili.AgentDrop.ActivityRegression</string>
<key>CFBundleName</key><string>Activity Regression</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
trap 'rm -rf "$FIXTURE_DIR"' EXIT
"$APP_DIR/Contents/MacOS/ActivityRegression" "$@"
