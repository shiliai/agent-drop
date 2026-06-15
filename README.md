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

## Planned CLI

The Finder integration will use the CLI as its core helper:

```bash
agent-drop targets
agent-drop send --target devbox file.png spec.pdf
agent-drop doctor
```

Interactive CLI use may also be supported:

```bash
agent-drop send file.png
```

In that mode, Agent Drop can ask which SSH target to use.

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

## Status

Agent Drop is in the design stage. The repository currently contains the V1 product and implementation direction, with development planned on a separate branch after the initial `main` setup.
