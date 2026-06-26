# Agent Drop Pull Design

## Summary

Agent Drop should support the reverse workflow: pulling files or folders from a known SSH host back to the Mac. The first version should keep Agent Drop's existing path-handoff model while adding a better macOS entry point:

1. Copy or type a remote path from an SSH session or remote agent response.
2. Open `Agent Drop -> Pull from...`.
3. Pick an SSH target if it was not inferred from the path.
4. Download the remote file or folder into `~/Downloads/Agent Drop/`.
5. Copy the final local path or paths to the Mac clipboard.

The CLI provides the reliable core:

```bash
agent-drop pull --target devbox ~/runs/output.png /tmp/build-artifacts
```

The Finder/App UI is a thin wrapper around the same core behavior.

## Goals

- Add a reverse transfer workflow from remote SSH hosts to the local Mac.
- Support files and folders.
- Default downloaded items to `~/Downloads/Agent Drop/`.
- Never overwrite local files or folders; auto-rename conflicts with the existing `name-2.ext` pattern.
- Accept pasted paths such as `~/result.png`, `/tmp/out.zip`, and `devbox:~/result.png`.
- Auto-prefill the pull window from the clipboard when it looks like a remote path.
- Use SSH targets discovered from the same config and active-session sources as upload.
- Use `rsync` for normal transfers.
- Use remote `tar` as an internal optimization for large directories, then auto-extract locally so the user still sees a normal folder.
- Record download results in history alongside upload results.
- Copy final local paths to the clipboard on success.

## Non-Goals

- No remote file browser in the first version.
- No bidirectional sync.
- No project-directory binding.
- No user-facing tar archive output for the automatic large-directory path.
- No settings UI for the tar threshold in the first version.
- No overwrite mode in the first version.

## User Experience

The Finder menu should keep the current upload flow and add one fixed pull entry:

```text
Agent Drop
  devbox
  gpu-box
  Pull from...
```

Selecting a target still uploads the current Finder selection, preserving the V1 behavior. Selecting `Pull from...` opens a small Agent Drop window with:

- an SSH target picker,
- a remote paths text field or multiline field,
- a destination note showing `~/Downloads/Agent Drop/`,
- a Download button,
- inline status for progress, success, and failure.

When the window opens, Agent Drop checks the clipboard. If the clipboard contains a plausible remote path, the path field is prefilled. If the path is in `host:path` form and `host` matches a discovered SSH target name or connect name, that target is selected automatically and the path field stores the path part.

Examples:

```text
~/runs/output.png
/tmp/build-artifacts
devbox:~/runs/output.png
```

On success, the clipboard receives local paths:

```text
~/Downloads/Agent Drop/output.png
~/Downloads/Agent Drop/build-artifacts
```

## Architecture

### DownloadService

`DownloadService` should live in `AgentDropCore` and own the durable pull behavior:

- receive a target, one or more remote paths, and a local destination root,
- inspect each remote path,
- reserve a non-overwriting local destination name,
- choose a transfer strategy,
- run the transfer,
- write final local paths to the clipboard when requested,
- clean up reserved or partial local outputs after failure,
- return structured results for CLI, App, and Finder callers.

### RemotePathParser

`RemotePathParser` should parse path input independently from UI code. It should understand:

- `~/path`
- `/absolute/path`
- `host:~/path`
- `host:/absolute/path`
- newline-separated paths

For `host:path`, the parser should return both the optional host hint and the remote path. Relative paths without `~/` are not part of the first version because they depend on an unknown remote working directory.

### LocalNamePlanner

Local naming should follow the existing upload conflict pattern:

```text
output.png
output-2.png
output-3.png

build-artifacts
build-artifacts-2
build-artifacts-3
```

This can reuse the current `RemoteNamePlanner` by extracting a more general `NamePlanner`, or by introducing a parallel `LocalNamePlanner` with the same behavior.

The local reservation step should be atomic:

- files are reserved by creating the destination file exclusively,
- directories are reserved with `mkdir`,
- failed transfers remove the reserved output.

### DownloadTransferPlanner

`DownloadTransferPlanner` should inspect each remote path over SSH and choose the transfer strategy:

- regular file: `rsync`,
- small directory: `rsync`,
- large directory: `tar` stream with local auto-extract.

The first version should use a fixed threshold of 200 files for the tar path. The remote hosts are expected to be Ubuntu machines where `tar` is available.

### Transfer History

The current history model is upload-specific. Download support should either add `DownloadHistoryEntry` or evolve the model into a neutral `TransferHistoryEntry`.

The App should be able to show both directions:

- upload records copy remote paths,
- download records copy local paths.

Download records should store:

- direction: download,
- target name,
- remote paths,
- local display paths,
- local file names,
- status,
- created time,
- short error message when failed.

## Transfer Behavior

Downloaded items are placed under:

```text
~/Downloads/Agent Drop/
```

The destination root is created if needed.

For each remote path, Agent Drop uses the remote basename as the local name:

```text
~/runs/output.png -> ~/Downloads/Agent Drop/output.png
/tmp/build-artifacts -> ~/Downloads/Agent Drop/build-artifacts
```

If that name already exists, Agent Drop chooses the next suffix:

```text
output-2.png
build-artifacts-2
```

### Files

Regular files transfer with `rsync -a`:

```text
rsync -a devbox:REMOTE_PATH LOCAL_RESERVED_PATH
```

### Small Directories

Small directories transfer with `rsync -a`, copying the directory contents into the reserved local directory:

```text
rsync -a devbox:REMOTE_PATH/ LOCAL_RESERVED_DIR/
```

The visible result is a normal folder named after the remote directory.

### Large Directories

Large directories use remote `tar` as an internal transfer optimization:

```text
ssh devbox tar -C REMOTE_DIR -czf - . | tar -xzf - -C LOCAL_RESERVED_DIR
```

The implementation should avoid leaving the remote host with a temporary archive. The local result should be auto-extracted into the reserved destination directory, which may have an auto-renamed local name such as `build-artifacts-2`. Users should not see a `.tar.gz` unless a future explicit archive mode is added.

## Error Handling

- No target selected: show a clear error and do not transfer.
- No path entered: show a clear error and do not transfer.
- Relative remote path without `~/` or `/`: reject with a clear message.
- Host hint conflicts with the selected target: ask the user to resolve the mismatch before downloading.
- Remote path missing: fail without updating the clipboard.
- Remote path is neither file nor directory: fail without updating the clipboard.
- Remote inspection fails: fail without updating the clipboard.
- Destination reservation fails: fail without updating the clipboard.
- Transfer fails: remove the reserved local output and do not update the clipboard.
- Clipboard write fails after successful transfer: keep the downloaded files and report that paths could not be copied.

The first version should use conservative all-or-nothing clipboard behavior. If any requested path fails, the clipboard should not be changed. Already completed outputs from earlier paths in the same request may remain, but the failed request should be recorded as failed and should not claim all paths were copied.

## CLI

Add:

```bash
agent-drop pull --target <target> <remote-paths...>
```

The target resolution behavior should match `send`:

- if `--target` is present, use it,
- if exactly one target is available and no target is given, use it,
- otherwise fail with a clear message.

The CLI prints final local display paths on success. It should not provide an interactive remote browser.

## App and Finder Integration

The Finder Sync extension should add a fixed `Pull from...` item under the existing `Agent Drop` menu. That item should open the containing app into a pull window or route.

The containing app should own the pull form because it is better suited than Finder Sync for text input, target selection, validation, and status. The App can call `DownloadService` directly and record history to the same store used for Finder actions.

The Finder extension should remain a thin menu surface. It should not implement the pull workflow itself.

## Testing Strategy

Core XCTest coverage should include:

- remote path parsing for `~/x`, `/x`, `host:~/x`, `host:/x`, and multiline input,
- rejection of unsupported relative paths,
- host-hint matching and mismatch handling,
- local conflict naming for files and folders,
- local reservation and cleanup after failed transfers,
- remote inspection command construction,
- transfer planning for files, small directories, and large directories,
- `rsync` command construction,
- tar stream command construction and shell quoting,
- no clipboard update on failed transfer,
- clipboard payload on successful transfer,
- history encoding for upload and download records,
- CLI parsing for `pull --target`.

Manual verification should include:

- `swift test` run serially,
- `agent-drop pull --target <host> ~/some-file`,
- repeated pull of the same file to confirm `-2` naming,
- pull of a small remote directory,
- pull of a large remote directory that triggers tar,
- App pull form with clipboard prefill,
- Finder `Pull from...` opens the pull form,
- App history shows download records and `Copy Paths` copies local paths,
- Xcode build of the app and Finder Sync extension with `CODE_SIGNING_ALLOWED=NO`.
