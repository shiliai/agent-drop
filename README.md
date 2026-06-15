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

Build the app and Finder Sync extension:

```bash
xcodebuild -project AgentDrop.xcodeproj -scheme AgentDrop -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Run the CLI during development:

```bash
swift run agent-drop doctor
swift run agent-drop targets
swift run agent-drop send --target devbox ./demo.png
```

Agent Drop uses a UTC `YYYY-MM-DD` folder for uploaded file paths.

The Finder extension may need to be enabled in System Settings after building the app locally.

## Status

Agent Drop V1 is implemented on this branch. The repository includes the Swift package/core, CLI, macOS app, Finder Sync extension, core tests, XcodeGen project configuration, and documented local test/build workflow.
