# Finder Extension Availability Design

## Problem

Agent Drop can be installed correctly while the Finder right-click workflow is unavailable. The failure presents the same way to users, but there are two confirmed root causes:

1. macOS can register `ai.shili.AgentDrop.FinderSync` without enabling it in System Settings. In that state `/Applications/Agent Drop.app` contains the extension, but Finder does not show the Agent Drop menu until the user enables the Finder extension and Finder reloads.
2. The Finder Sync extension currently registers only local user directories. SMB and other mounted volume paths, such as `/Volumes/home/database/2026/AS/数据湖仓/minio`, are outside the registered scope, so Finder never asks Agent Drop for a menu there even when the extension is enabled and running.

## Goals

- Show an in-app setup notice when the Finder extension appears disabled, unregistered, or otherwise unavailable.
- Keep the notice non-blocking so clipboard upload, pull, and history workflows still work.
- Provide a direct action to open the macOS extension settings page.
- Register mounted volumes under `/Volumes` for Finder Sync so SMB, external drives, and network volumes can show the Agent Drop menu.
- Cover the core status parsing and Finder Sync directory scope with tests.

## Non-Goals

- Do not automatically enable the Finder extension with `pluginkit -e use`; enabling third-party extensions is user-controlled system setup.
- Do not build a full permissions wizard.
- Do not persist custom user-selected Finder Sync roots in this slice.

## Architecture

Add a small core status boundary that interprets Finder extension registration state from `pluginkit` output. The app will run `pluginkit` through the existing command runner, convert the result into a compact status enum, and render a setup notice on `Transfer > Drop` only when attention is needed.

Update `FinderSyncDirectoryScope` to include `/Volumes` alongside the existing local home, Desktop, Documents, Downloads, and `/System/Volumes/Data/...` mirror paths. The Finder Sync extension will continue to set `FIFinderSyncController.default().directoryURLs` from that core helper, so one tested place controls the menu availability scope.

## App Behavior

On app launch and when the app becomes active, `DropLandingView` refreshes Finder extension availability. If the status needs setup, the Finder workflow card shows a compact warning area with:

- the short reason,
- `Open System Settings`,
- `Restart Finder`.

The existing `Open Finder` and `Pull instead` actions remain visible. The notice should not disable clipboard drop or any transfer status.

## Detection Details

The detection command is:

```bash
/usr/bin/pluginkit -m -A -p com.apple.FinderSync
```

The parser looks for `ai.shili.AgentDrop.FinderSync`. Lines prefixed with `+` indicate the extension is enabled. A matching line without `+` means the extension is registered but disabled. No matching line means the extension is not registered or not installed. Command failure is reported as an unknown status that still gives the same setup action.

## Testing

Add focused XCTest coverage for:

- parsing enabled `pluginkit` output,
- parsing registered-but-disabled output,
- parsing missing output,
- handling command failure,
- `FinderSyncDirectoryScope` including `/Volumes`.

Manual verification should include:

- local home/Desktop right-click still shows Agent Drop,
- SMB path under `/Volumes/home/...` shows Agent Drop after installing the rebuilt app and restarting Finder,
- disabled extension state shows setup guidance in the app.
