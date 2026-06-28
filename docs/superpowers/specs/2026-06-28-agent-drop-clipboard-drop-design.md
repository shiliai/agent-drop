# Agent Drop Clipboard Drop Design

## Summary

Agent Drop should make the app's Drop page useful immediately after a Mac screenshot. When the user opens Agent Drop, the app checks the Mac clipboard for a valid local upload source. If it finds one, the Drop page shows a ready clipboard card. After the user selects an SSH host, they can click `Drop Clipboard` to upload the clipboard item through the existing upload pipeline. On success, Agent Drop copies the final remote path or paths to the Mac clipboard, so the user can paste the path into an SSH session or remote terminal.

The first version should support two local clipboard sources:

- screenshot/image data copied directly to the clipboard,
- local file URLs copied from Finder or another macOS app.

Plain text is intentionally ignored. This prevents the common follow-up case where the clipboard still contains the previous upload's remote path, such as `~/.agent-inbox/2026-06-28/demo.png`, and Agent Drop incorrectly offers to drop it again.

## Goals

- Add a `Drop Clipboard` action to the existing `Transfer -> Drop` page.
- Detect valid local clipboard sources when the app opens, becomes active, or returns to the Drop page.
- Treat local file URLs as ready only when every path exists and is a regular file or directory.
- Treat clipboard image data as ready by writing it to a temporary PNG file.
- Use macOS-style screenshot naming for generated image files: `Screenshot YYYY-MM-DD at HH.mm.ss.png`.
- Preserve actual file and directory names for file URL clipboard sources.
- Support multiple local file URLs in one clipboard drop.
- Reuse `UploadService.upload(sources:target:)` so remote directory creation, remote conflict renaming, `rsync`, and Mac clipboard writes stay consistent with existing drops.
- Record clipboard drops in transfer history as normal uploads.
- Avoid treating plain text, remote paths, or invalid local paths as droppable content.

## Non-Goals

- No global clipboard monitor in the first version.
- No automatic upload immediately after taking a screenshot.
- No remote-host clipboard write with tools such as `xclip` or `wl-copy`.
- No new top-level `Clipboard` or `Screenshot` transfer mode.
- No image editing, preview cropping, annotation, or format selection.
- No support for file promises or delayed drag/paste providers in the first version.
- No attempt to infer local files from plain text paths.

## User Experience

The current `Transfer -> Drop` page stays the entry point. It should show the existing Finder workflow and add a clipboard card.

When no valid local clipboard source exists, the card shows a quiet empty state and the `Drop Clipboard` button is disabled. Plain text, remote paths, and invalid paths all keep the action disabled.

When a valid local clipboard source exists but no host is selected, the clipboard card shows a ready state, but `Drop Clipboard` remains disabled with a short prompt to select a host first. Readiness and executability are separate:

- clipboard content decides whether there is something to drop,
- host selection decides whether the drop can run.

When a valid local clipboard source exists and a host is selected, `Drop Clipboard` is enabled. The card summary should distinguish the source without over-explaining:

- `Clipboard item ready` with `Screenshot 2026-06-28 at 14.32.10.png` for image data,
- `demo.png ready` for one local file URL,
- `3 local items ready` for multiple local file URLs.

The Drop page should include a small refresh control for rechecking the clipboard. The app also rechecks automatically on app activation and when switching back to Drop, but it should not continuously poll the pasteboard.

During upload, the button shows progress and is disabled. On success, the UI shows the copied remote path or paths and the Mac clipboard receives the same newline-separated remote paths. On failure, the UI shows a short error and the Mac clipboard is not changed.

## Clipboard Source Detection

Detection should be modeled as a small core-friendly resolver that operates on a platform-neutral clipboard snapshot. The app layer can adapt `NSPasteboard` into that snapshot.

The resolver should return one of:

- `ready`: upload sources plus display metadata,
- `empty`: no droppable local source,
- `invalid`: local-looking data was present but cannot be uploaded.

Resolution order should prefer the most explicit local source:

1. Valid local file URLs.
2. Clipboard image data.
3. Empty for all text-only clipboard content.

For file URLs, every item must pass `FileSelection.validate`. If any copied local item is missing or unsupported, the result is invalid and the upload button remains disabled. This all-or-nothing rule avoids silently uploading only part of a copied Finder selection.

For image data, the app writes a PNG into a temporary staging directory and creates one `UploadSourceFile` with:

- `sourceURL`: the generated temporary PNG,
- `remoteName`: the generated screenshot name,
- `localDisplayName`: the same screenshot name,
- `isDirectory`: `false`.

Generated screenshot names use the local system time and the current app clock. If the generated name conflicts remotely, the existing remote name planner still applies and may produce names such as `Screenshot 2026-06-28 at 14.32.10-2.png`.

Plain text should not be parsed into local paths in the first version. This is deliberate even when text looks like `/Users/chris/Desktop/demo.png`; requiring an actual file URL avoids false positives and keeps the post-upload remote-path clipboard case safe.

## Upload Flow

`DropLandingView` owns the app-level interaction state:

- current clipboard resolution,
- whether a clipboard drop is running,
- success or failure status,
- selected SSH target from the shared host list.

When the user clicks `Drop Clipboard`, the view starts a single operation:

1. Recheck dependencies needed for upload.
2. Ensure an SSH target is selected.
3. Resolve or reuse the current clipboard upload sources.
4. Call `UploadService.upload(sources:target:)`.
5. Append a succeeded upload history entry.
6. Show the final remote path or paths.

The upload service remains the durable boundary for transfer behavior. The new feature should not duplicate remote directory creation, remote reservation, `rsync`, or clipboard writing in SwiftUI.

Temporary screenshot files should be stored under the same broad temporary area used for staged uploads, but in a feature-specific subdirectory or operation directory so cleanup is straightforward. Cleanup should happen after success or failure. If cleanup fails, the upload result should not be changed; the app can ignore the cleanup error.

## History

Clipboard drops should record transfer history as normal uploads:

- direction: `upload`,
- target name,
- local display names from the generated screenshot name or actual file names,
- final remote display paths,
- status and short error message when failed.

History should not need a new direction or schema. Existing upload history rendering and copy behavior should continue to work.

If the upload succeeds but writing history fails, the uploaded file remains on the remote host and the Mac clipboard remains set to the final remote path or paths. The UI should report that history could not be recorded.

## Error Handling

- No valid local clipboard source: disable `Drop Clipboard` and show a quiet empty state.
- Plain text or remote path text only: treat as no valid local clipboard source, not as an error.
- Invalid local file URL: show an invalid clipboard item message and keep `Drop Clipboard` disabled.
- Valid clipboard source but no host: show the ready card and prompt the user to choose a host; keep the button disabled.
- Missing upload dependency: show the existing dependency feedback and do not start upload.
- Temporary PNG creation fails: show that the clipboard image could not be prepared and do not call upload.
- Upload fails: do not change the Mac clipboard; record failed history when possible.
- Clipboard write fails after upload: preserve the uploaded remote file and show the existing clipboard failure message.
- History write fails after successful upload: preserve the upload and clipboard result, and show that history recording failed.

## Testing Strategy

Core XCTest coverage should include:

- resolving one valid local file URL,
- resolving multiple valid local file URLs,
- resolving a valid local directory URL,
- rejecting a file URL whose path no longer exists,
- rejecting unsupported local items from `FileSelection.validate`,
- ignoring plain text and remote-looking path text,
- generating a screenshot upload source with the expected display name,
- ensuring file URL sources preserve actual file and directory names,
- preserving all-or-nothing behavior for mixed valid and invalid local file URLs.

App-level or focused unit coverage should include:

- Drop opens with `Drop Clipboard` disabled when the clipboard is text-only,
- Drop shows a ready card when a screenshot or valid file URL is available,
- `Drop Clipboard` remains disabled until a host is selected,
- a successful clipboard drop records upload history and displays remote paths,
- a failed clipboard drop records failed history and does not report copied paths.

Manual verification should include:

- take a screenshot directly to the clipboard, open Agent Drop, select a host, drop it, and paste the resulting remote path into an SSH terminal,
- copy multiple Finder files, open Agent Drop, select a host, drop them, and verify multiple remote paths are copied,
- complete a drop, reopen Agent Drop while the remote path remains in the clipboard, and verify the button stays disabled.
