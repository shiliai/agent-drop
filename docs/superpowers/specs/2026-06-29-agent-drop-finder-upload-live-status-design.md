# Agent Drop Finder Upload Live Status Design

## Summary

Finder-triggered uploads can take time, and today the user only gets reliable in-app feedback after the upload finishes and history is refreshed. This design adds live transfer feedback for Finder uploads by combining:

- A global status bar message that is visible from any app section.
- A live History row that appears when the Finder upload starts and updates in place when the upload succeeds or fails.

The goal is to make `Agent Drop -> <target>` feel responsive without forcing the Finder extension to open or focus the app.

## Goals

- Show that a Finder upload is running when the user opens Agent Drop during the transfer.
- Keep the feedback visible while the user is on the `Transfer` section.
- Show a live History row for users who open `History` for more detail.
- Update the same History row from `running` to `succeeded` or `failed` when the upload finishes.
- Preserve the existing Finder workflow, badges, diagnostics log, clipboard behavior, and notifications.
- Keep cross-process communication simple by reusing the existing Finder extension history file and app file watcher.

## Non-Goals

- No progress percentage or byte-level transfer progress.
- No cancellation, retry, or pause action.
- No concurrent transfer queue UI.
- No new app-to-extension IPC channel.
- No App Group migration.
- No automatic app focus after every Finder upload.
- No change to clipboard-drop or pull workflows beyond keeping shared status semantics compatible.

## User Experience

When the user right-clicks files in Finder and chooses `Agent Drop -> x570`, the Finder extension writes a `running` transfer entry before staging and uploading starts.

If the user opens Agent Drop while the upload is running:

- The bottom global status bar shows a blue activity state such as `Uploading 2 files to x570...`.
- This message is visible whether the user is on `Transfer` or `History`.
- The status text can include a compact file summary when it fits, for example `design.pdf, screenshots`.

If the user opens `History`:

- The newest row shows an upload-in-progress icon and summary, for example `2 files uploading`.
- Selecting the row shows target, start time, and local file names.
- Remote paths are not shown until the upload succeeds.
- The detail view explains that remote paths will appear after success.

When the upload finishes:

- Success updates the same row to `succeeded`, fills in remote paths, and keeps copy-path behavior.
- Failure updates the same row to `failed` with a short error message.
- The global status bar switches to the existing success or failure summary.

If the app is opened after the transfer has already completed, the user sees only the final result, as today.

## Data Model

Extend `UploadHistoryEntry.Status` with:

- `running`
- `succeeded`
- `failed`

The JSON model remains backward compatible:

- Existing history files with `succeeded` and `failed` continue decoding.
- New `running` entries decode in newer app versions.
- `copyPayload` remains available only for successful entries with copyable paths.

Add a factory for Finder upload start entries:

```text
UploadHistoryEntry.uploadStarted(
  id,
  targetName,
  fileURLs,
  createdAt
)
```

This entry records:

- Stable transfer id.
- Direction: upload.
- Target name.
- Original selected file names.
- Start time.
- Status: running.
- Empty remote paths.
- No error message.

The Finder extension should generate one id for a transfer and reuse it for the final success or failure update.

## Storage

`UploadHistoryStore` remains the single persistence boundary for the shared history file:

```text
~/Library/Containers/ai.shili.AgentDrop.FinderSync/Data/Library/Application Support/Agent Drop/upload-history.json
```

Add an update operation:

```text
upsert(entry)
```

Behavior:

- If an entry with the same id exists, replace it.
- If no entry exists, insert it.
- Sort newest first and trim to the configured limit.
- Keep the existing same-process queue and cross-process file lock.
- Preserve corrupt-history behavior.

This lets the Finder extension write `running` first, then replace the same entry with `succeeded` or `failed`.

## Finder Sync Behavior

For a valid Finder selection and target:

1. Validate dependencies and selected files as today.
2. Create a stable transfer id.
3. Write a `running` history entry before staging begins.
4. Stage and upload files as today.
5. On success, update the same id to `succeeded`, copy remote paths, badge files, notify, and write diagnostics.
6. On failure, update the same id to `failed`, badge files, notify, and write diagnostics.

If the initial `running` history write fails, the upload should still proceed. Diagnostics should record the history-write failure. The final success or failure entry should still be attempted.

Dependency and selection failures that happen before a valid transfer exists can continue to use notifications and diagnostics only. They do not need a running row because no transfer started.

## App Behavior

The app already watches the history file. On refresh:

- If the newest relevant entry is `running`, set the global transfer summary to a progress message.
- If the entry transitions to `succeeded` or `failed`, show the matching final summary.
- If there are no active entries, keep the existing idle timestamp behavior.

The `Transfer` section does not need a new activity panel for this slice. The global status bar is the feedback surface while the user remains on Transfer.

The `History` row and detail UI should handle all three statuses:

- `running`: blue activity icon, upload-in-progress copy, no copy button.
- `succeeded`: green success icon, copy button when paths exist.
- `failed`: red failure icon, short error message.

## Stale Running Entries

A `running` entry can become stale if the Finder extension crashes, is killed, or the machine sleeps during a transfer. The app should avoid showing an endless active upload.

For this slice:

- Treat a running entry older than a conservative timeout as stale for display.
- Recommended timeout: 30 minutes.
- Stale rows should show an unknown or interrupted status in the UI copy, but the stored status can remain `running`.
- The global status bar should not keep showing progress for stale entries.

This keeps the data model simple while preventing misleading live status.

## Error Handling

- History write failure must not block upload execution.
- Final history update failure should be recorded in diagnostics.
- If the app cannot read history, keep the existing `History unavailable` behavior.
- If the history file watcher misses an event, activation/manual refresh should still load the latest state.
- If a final update arrives without a matching running entry, `upsert` should insert it so history still records the transfer.

## Testing

Add focused XCTest coverage for:

- Encoding and decoding a `running` entry.
- Legacy `succeeded` and `failed` entries still decoding.
- `copyPayload` returning nil for running entries.
- `UploadHistoryStore.upsert` replacing an entry with the same id.
- `upsert` inserting a final entry when no running entry exists.
- Store ordering and trimming after replacement.
- Status summary deriving progress text from the newest non-stale running upload.
- Stale running entries not driving the global status bar.

Manual verification should cover:

- Start a Finder upload and immediately open Agent Drop on `Transfer`: status bar shows upload progress.
- Switch to `History` during the upload: a running row appears with local file names.
- Successful upload updates the same row with remote paths and copy action.
- Failed upload updates the same row with a short failure message.
- Existing Finder badges, notifications, diagnostics, and clipboard copy still work.

## Rollout Notes

This is a small behavior extension on top of the existing history architecture. It intentionally avoids a separate activity store or IPC channel. If Agent Drop later supports multiple simultaneous transfers, progress percentages, cancellation, or a transfer queue, the live History row can become the source for a richer activity panel.
