# Agent Drop Transfer Navigation Design

## Summary

Agent Drop's app window should treat file transfer as the primary job and transfer history as supporting activity. The current app opens on `History` and places `Pull from...` beside it as an equal tab. That makes the record view feel like the front door, while the actual product actions are split between Finder and the second tab.

The selected mode is a transfer-first layout:

- `Transfer` is the primary navigation item.
- `Drop` and `Pull from...` are mode choices inside `Transfer`.
- SSH hosts are shared transfer context, not owned by either Drop or Pull.
- `History` is a secondary navigation item after `Transfer`.
- The app opens on `Drop`, not `History`.
- The bottom status bar remains a window-level element.

## Goals

- Make Drop and Pull the first things users see.
- Keep History visible, but make it clearly secondary.
- Preserve the bottom status bar with refresh time and version display.
- Make host selection reusable between Drop and Pull.
- Preserve the existing Finder-first upload workflow.
- Reuse the existing Pull form and History detail views where possible.
- Keep the change focused on app-window organization, not transfer behavior.

## Non-Goals

- No new upload engine inside the app.
- No remote file browser.
- No settings screen.
- No change to CLI behavior.
- No change to history file format.

## User Experience

The app window uses a left navigation column with the main product areas:

```text
Transfer
History
```

`Transfer` is selected by default. Inside the transfer workspace, the detail area uses a compact mode control for:

```text
Drop | Pull from...
```

Below the navigation/detail area, the app keeps a full-window status bar. It continues to show the current refresh or watcher state, the latest refresh time, and the app version. This bar is not owned by History; it remains visible when the user is on `Drop`, `Pull from...`, or `History`.

The transfer area has a shared hosts column next to the main navigation. This column lists discovered SSH targets once, and both transfer modes use the same selected host context. The hosts column header includes a compact refresh icon button. `Refresh Targets` should not be a large primary button in the main content area.

`Drop` is the default transfer mode. It explains the upload path in action-oriented UI terms and gives the user a small amount of practical control:

- use the shared selected host from the hosts column,
- offer a primary `Open Finder` action,
- keep wording concise so it feels like a tool surface, not a landing page.

Because upload is still Finder-first, the Drop panel does not ask users to choose files inside the app in this iteration. It should point them to Finder and reinforce the existing flow:

```text
Select files in Finder, right-click, then choose Agent Drop and a target.
```

`Pull from...` is the alternate transfer mode and keeps the existing pull form behavior:

- selected host context from the shared hosts column,
- remote paths field with host-prefixed input preserved when launched from a host hint,
- destination note,
- prominent download button inside the form panel,
- inline status.

`History` keeps the existing split-view list and detail behavior. Its empty state should mention both primary workflows:

```text
Drop files from Finder or pull remote paths to create transfer history.
```

## Architecture

Introduce a small navigation model in `AgentDropCore` so route behavior can be tested outside SwiftUI:

- `AppSection.transfer`
- `AppSection.history`
- `TransferMode.drop`
- `TransferMode.pull`
- `TransferNavigationState`

The top-level window should switch from a tab view to a sidebar-style layout. The sidebar owns app-section navigation. The transfer workspace owns transfer mode selection.

The detail area renders one of:

- `TransferWorkspaceView`
- `UploadHistoryView`

`TransferWorkspaceView` contains the shared hosts column plus a detail pane that switches between:

- `DropLandingView`
- `PullFormView`

The host list is not inside `DropLandingView` or `PullFormView`. `TransferWorkspaceView` owns discovered targets, selected target, dependency feedback, and refresh. `DropLandingView` and `PullFormView` receive the selected target and refresh state from the workspace.

The bottom status bar should move out of `UploadHistoryView` into the top-level window shell. History can continue to drive refresh and watcher state, but the status presentation belongs to the app frame so it stays visible across the primary transfer screens.

`DropLandingView` can be intentionally lightweight. It should not introduce new transfer behavior. If no target is selected, it should ask the user to select a host from the shared hosts column. If a target cannot be discovered, the shell should show the same kind of dependency feedback already used by the pull form.

The existing URL route for `agent-drop://pull` should select `Transfer` and set the transfer mode to `Pull from...`.

## States

- Default app launch: `Transfer` selected with `Drop` as the active mode.
- Finder or URL route opens Pull: `Transfer` selected with `Pull from...` as the active mode.
- Target discovery: hosts appear in the shared hosts column and refresh through a compact icon button near the hosts header.
- Selected host: persists while switching transfer mode between Drop and Pull.
- Pull succeeds or fails: history refresh token updates as it does today.
- User selects History: existing history view loads and watches the history file.
- History unavailable: existing unavailable state is preserved.
- Bottom status bar: remains visible on every navigation selection and keeps showing refresh time plus version.

## Testing

Add focused tests for `TransferNavigationState`:

- default selection is Transfer with Drop mode,
- pull route selects Transfer with Pull mode,
- selecting History does not reset the last transfer mode,
- selected host can persist while switching transfer mode.

For the SwiftUI layout itself, verify with a macOS build and visual smoke test:

- app compiles,
- Pull can still record history refreshes,
- the bottom status bar remains visible outside History,
- History still renders existing transfer details.
