# Agent Drop V1 Design

## Summary

Agent Drop is a macOS local delivery tool for sending selected Finder files to a remote SSH development machine. V1 focuses on one workflow:

1. Select one or more files in Finder.
2. Right-click and open `Agent Drop`.
3. Pick a discovered SSH target from the submenu.
4. Upload the files to the remote `~/.agent-inbox/YYYY-MM-DD/` directory.
5. Copy the final remote file paths to the Mac clipboard.

V1 does not generate an agent prompt. The copied paths are the handoff surface: the user returns to an existing SSH terminal and pastes the paths into Codex, Claude Code, or another remote coding agent.

## Goals

- Run on macOS.
- Support Finder right-click delivery for files.
- Show SSH targets directly under a dynamic `Agent Drop` submenu.
- Discover targets from both `~/.ssh/config` and currently active SSH connections.
- Upload through standard `ssh` and `rsync`.
- Use a stable hidden remote inbox root: `~/.agent-inbox`.
- Group uploads by date with `YYYY-MM-DD` directories.
- Avoid overwriting remote files by automatically renaming conflicts.
- Copy final remote file paths, including file names, to the Mac clipboard.

## Non-Goals

- No prompt generation in V1.
- No bidirectional sync.
- No remote project directory integration.
- No directory upload in V1.
- No clipboard image or clipboard text upload in V1.
- No iOS sharing, Raycast, Alfred, or menu bar workflow in V1.
- No hard dependency on SSH session reuse. If SSH ControlMaster is configured, standard SSH tooling may reuse the underlying connection naturally.

## User Experience

The target interaction is a Finder context menu flow:

```text
Right-click selected file(s)
  Agent Drop
    devbox        active
    gpu-box       active
    work-ubuntu   config
```

Selecting a target immediately uploads the selected files. On success, Agent Drop shows a macOS notification:

```text
Uploaded 2 files to devbox
Copied remote paths to clipboard.
```

The clipboard contains one final remote path per uploaded file:

```text
~/.agent-inbox/2026-06-15/demo.png
~/.agent-inbox/2026-06-15/spec-2.pdf
```

For one selected file, the clipboard contains one path. For multiple selected files, it contains multiple newline-separated paths.

If a selected Finder item is a directory, V1 reports that directories are not supported yet and does not upload it.

## macOS Integration

Pure macOS Quick Actions are not the right fit for the target UX because they expose fixed actions and do not naturally provide a dynamic second-level SSH target submenu.

V1 should use a small native macOS app with a Finder Sync Extension for the right-click surface:

- The Finder Sync Extension contributes the `Agent Drop` context menu.
- The extension builds the SSH target submenu dynamically.
- Each submenu item launches the shared upload helper with the selected file paths and selected target.
- The native app provides installation/status/settings affordances if needed, but the CLI remains the core behavior boundary.

The command-line helper remains reusable outside Finder:

```bash
agent-drop targets
agent-drop send --target devbox file.png spec.pdf
agent-drop doctor
```

An interactive `agent-drop send file.png` can still prompt for a target in the terminal, but Finder actions should pass the target explicitly.

## Components

### CLI Helper

The `agent-drop` helper owns the durable behavior:

- Parse commands.
- Discover SSH targets.
- Validate local file inputs.
- Create the remote date directory.
- Resolve remote filename conflicts.
- Upload files with `rsync`.
- Copy final remote paths to the Mac clipboard.
- Return structured errors for the Finder extension and human-readable errors for terminal use.

### Finder Sync Extension

The extension owns Finder context menu presentation:

- Read the current Finder selection.
- Filter to regular files.
- Query or load discovered SSH targets.
- Render `Agent Drop -> SSH target` submenu items.
- Invoke the helper with selected file paths and target identity.
- Surface success or failure through notifications.

### SSH Target Discovery

Target discovery combines two sources:

- Stable configured targets from `~/.ssh/config`.
- Currently active SSH connections from local process or connection inspection.

Targets are merged and deduplicated. Active targets are listed first; config-only targets are listed after them.

For configured targets, use the SSH alias as the transfer target whenever possible:

```text
devbox
gpu-box
work-ubuntu
```

For active connections that do not map cleanly to an SSH config alias, display a usable `user@host` target if it can be reconstructed safely.

### Remote Inbox Layout

The remote root is fixed for V1:

```text
~/.agent-inbox
```

Each upload writes into the current local date directory:

```text
~/.agent-inbox/2026-06-15/
```

This date-level grouping keeps cleanup simple and avoids overly granular timestamp folders.

### Conflict Handling

V1 never overwrites existing remote files.

If the intended remote filename already exists, Agent Drop chooses the next available suffix:

```text
demo.png
demo-2.png
demo-3.png
```

For names without extensions:

```text
README
README-2
README-3
```

The clipboard always receives the final actual remote paths after conflict resolution.

## Data Flow

```text
Finder selection
  -> Finder Sync Extension
  -> selected target
  -> agent-drop helper
  -> ssh mkdir -p ~/.agent-inbox/YYYY-MM-DD
  -> remote existence checks for each file
  -> rsync each file to its final remote filename
  -> pbcopy newline-separated final remote paths
  -> macOS notification
```

## Error Handling

- No files selected: show a clear notification and exit.
- Directory selected: report unsupported item and do not upload that item.
- No SSH targets found: tell the user to add `~/.ssh/config` hosts or connect over SSH first.
- Target selection fails or target disappears: show the target name and failure.
- Remote directory creation fails: do not upload and do not modify the clipboard.
- Remote conflict checks fail: do not upload and do not modify the clipboard.
- Upload fails: do not modify the clipboard.
- Clipboard write fails: upload remains complete, but the notification says paths could not be copied.

## Testing Strategy

The CLI should be testable without live SSH:

- SSH config parsing.
- Active SSH connection parsing.
- Target merge, dedupe, and ordering.
- Date directory path generation.
- Remote filename conflict resolution.
- Command construction for `ssh` and `rsync`.
- Clipboard payload formatting.
- Error behavior that prevents clipboard updates after failed upload.

External commands should sit behind small process-running boundaries so tests can use fake executors.

Manual verification should cover:

- `agent-drop targets`.
- `agent-drop send --target <host> <file>`.
- Conflict rename behavior on a real SSH target.
- Finder right-click menu shows active and config targets.
- Finder upload copies final remote paths to the Mac clipboard.

## Open Implementation Notes

- The exact macOS project structure can be Swift app plus Finder Sync Extension plus embedded helper, or a Swift Package helper invoked by the app bundle.
- The extension should avoid slow SSH discovery directly on every menu open. A short-lived target cache can make the menu feel instant while `Refresh SSH Targets` forces an update.
- The helper should not depend on a shell profile. It should call system tools by absolute path or a controlled PATH.
