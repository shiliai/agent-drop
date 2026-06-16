# Agent Drop

Agent Drop is a macOS tool for sending local files to a remote SSH development machine so coding agents can read them from a stable inbox.

The first version is designed around one fast workflow:

```text
Right-click selected file(s)
  Agent Drop
    devbox
    gpu-box
    work-ubuntu
```

After a target is selected, Agent Drop uploads the files to the remote machine and copies the final remote file paths to the Mac clipboard.

```text
~/.agent-inbox/2026-06-15/demo.png
~/.agent-inbox/2026-06-15/spec-2.pdf
```

You can then paste those paths into an existing SSH terminal for Codex, Claude Code, or another remote coding agent.

## V1 Goals

- Run on macOS.
- Support Finder right-click delivery for selected files.
- Show discovered SSH targets under an `Agent Drop` submenu.
- Discover targets from `~/.ssh/config` and active SSH connections.
- Upload through standard `ssh` and `rsync`.
- Store files under the remote inbox root `~/.agent-inbox`.
- Group uploaded files by date: `~/.agent-inbox/YYYY-MM-DD/`.
- Avoid overwrites by renaming conflicts, for example `demo-2.png`.
- Copy final remote file paths, including filenames, to the Mac clipboard.

## CLI Usage

Agent Drop includes a CLI for checking dependencies, listing SSH targets, and sending files to an explicit target:

```bash
agent-drop targets
agent-drop doctor
agent-drop send --target <target> <files...>
```

The CLI does not implement an interactive target picker.

## Not In V1

- No prompt generation.
- No bidirectional sync.
- No remote project directory integration.
- No directory upload.
- No clipboard image or clipboard text upload.
- No Raycast, Alfred, iOS sharing, or menu bar workflow.

## Design

The current V1 design is documented in:

[docs/superpowers/specs/2026-06-15-agent-drop-design.md](docs/superpowers/specs/2026-06-15-agent-drop-design.md)

## Development

Run the core tests:

```bash
swift test
```

Generate the Xcode project:

```bash
xcodegen generate
```

Build the app and Finder Sync extension without signing checks:

```bash
xcodebuild -project AgentDrop.xcodeproj -scheme AgentDrop -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

For local Finder Sync testing, use Xcode automatic signing with an Apple
Development certificate. Both the app target and Finder Sync extension target
should use the same Team. The checked-in `project.yml` contains the development
team and entitlements used for this local flow.

Build a signed Debug app:

```bash
xcodebuild -project AgentDrop.xcodeproj -scheme AgentDrop -configuration Debug build
```

Install the signed app locally:

```bash
APP_SRC="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*/AgentDrop-*/Build/Products/Debug/AgentDrop.app" -type d | sort | tail -n 1)"
APP_DEST="$HOME/Applications/Agent Drop.app"

test -n "$APP_SRC"
pkill -x AgentDrop || true
pkill -x AgentDropFinderSync || true
rm -rf "$APP_DEST"
cp -R "$APP_SRC" "$APP_DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R -trusted "$APP_DEST"
xcrun pluginkit -a "$APP_DEST/Contents/PlugIns/AgentDropFinderSync.appex" || true
xcrun pluginkit -e use -i ai.shili.AgentDrop.FinderSync || true
open -n "$APP_DEST"
killall Finder
```

If the right-click menu is not visible, open System Settings > Login Items &
Extensions > Extensions and enable the Agent Drop Finder extension. Restart
Finder after changing the extension state.

Run the CLI during development:

```bash
swift run agent-drop doctor
swift run agent-drop targets
swift run agent-drop send --target devbox ./demo.png
```

Agent Drop uses a UTC `YYYY-MM-DD` folder for uploaded file paths.

## Finder Extension Notes

- The Finder menu is `Agent Drop -> <SSH target>`.
- The root menu item includes a small template upload icon.
- On upload success or failure, Finder badges the selected file briefly.
- The extension writes diagnostics to
  `~/Library/Containers/ai.shili.AgentDrop.FinderSync/Data/Library/Logs/AgentDropFinderSync.log`.
- macOS notification delivery from Finder Sync is best-effort. A reliable
  in-app upload history and feedback surface is tracked in
  [issue #2](https://github.com/shiliai/agent-drop/issues/2).

## Upload History

Agent Drop records recent Finder uploads in the Finder extension container:

    ~/Library/Containers/ai.shili.AgentDrop.FinderSync/Data/Library/Application Support/Agent Drop/upload-history.json

The app reads that file to show `Recent Uploads`. Successful rows include
remote paths that can be copied again. Failed rows include a short error.

For this developer build path, the containing app is intentionally
unsandboxed so it can read the Finder extension history file without requiring
an Apple Developer Program App Group. A later signed and notarized release can
migrate the store to an App Group container.

Manual Finder smoke test:

```bash
TEST_FILE="$HOME/Downloads/agent-drop-ui-test.png"
printf 'AGENT_DROP_PENDING' | pbcopy
open -R "$TEST_FILE"
```

Then right-click the file in Finder, choose `Agent Drop -> x570 config` or
another configured target, and verify:

```bash
pbpaste
ssh x570 'd="$HOME/.agent-inbox/$(date +%F)"; ls -l "$d"/agent-drop-ui-test*; wc -c "$d"/agent-drop-ui-test*'
tail -n 80 "$HOME/Library/Containers/ai.shili.AgentDrop.FinderSync/Data/Library/Logs/AgentDropFinderSync.log"
```

Expected: `pbpaste` contains the final remote path, the remote file exists, and
the diagnostic log records `upload success`.

After a Finder upload, verify history was written:

    HISTORY="$HOME/Library/Containers/ai.shili.AgentDrop.FinderSync/Data/Library/Application Support/Agent Drop/upload-history.json"
    test -f "$HISTORY"
    python3 -m json.tool "$HISTORY" | sed -n '1,80p'

Open `Agent Drop.app` and confirm the upload appears in `Recent Uploads`.
Select the upload, click `Copy Paths`, and verify:

    pbpaste

## Status

Agent Drop V1 is implemented on this branch. The repository includes the Swift package/core, CLI, macOS app, Finder Sync extension, core tests, XcodeGen project configuration, and documented local test/build workflow.
