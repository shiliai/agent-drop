# Repository Guidelines

## Project Structure & Module Organization

Agent Drop is a Swift 6 macOS project with a SwiftPM core and XcodeGen app wrapper.

- `Sources/AgentDropCore/` contains shared upload, pull/download, target discovery, history, shell, and parser logic.
- `Sources/AgentDropCLI/` contains the `agent-drop` command-line entry point.
- `Sources/AgentDropApp/` contains the SwiftUI macOS app, app assets, Info.plist, and app entitlements.
- `Sources/AgentDropFinderSync/` contains the Finder Sync extension and its entitlements.
- `Tests/AgentDropCoreTests/` contains XCTest coverage for the core package.
- `docs/assets/` stores README screenshots; `docs/superpowers/` stores design and implementation notes.

## Build, Test, and Development Commands

- `swift test` runs the core XCTest suite. Run it serially; parallel SwiftPM runs can contend on `.build`.
- `swift run agent-drop doctor` checks required local tools.
- `swift run agent-drop targets` lists discovered SSH targets.
- `swift run agent-drop send --target devbox ./demo.png ./folder` uploads paths from the CLI.
- `swift run agent-drop pull --target devbox ~/runs/output.png` downloads remote paths into `~/Downloads/Agent Drop/`.
- `xcodegen generate` regenerates `AgentDrop.xcodeproj` from `project.yml`.
- `xcodebuild -project AgentDrop.xcodeproj -scheme AgentDrop -configuration Debug build CODE_SIGNING_ALLOWED=NO` verifies the app and extension compile without signing.
- `xcodebuild -project AgentDrop.xcodeproj -scheme AgentDrop -configuration Debug build` builds a locally signed Debug app.

## Coding Style & Naming Conventions

Use Swift 6 conventions: four-space indentation, `PascalCase` for types, `camelCase` for functions/properties, and files named after their main type. Prefer testable core services in `AgentDropCore` over duplicating logic in the app or Finder extension. Keep shell interaction isolated and safely quoted, especially for remote paths used by `ssh`, `rsync`, and `tar`.

## Testing Guidelines

Tests use XCTest and should live in `Tests/AgentDropCoreTests/`. Name files after the unit under test, for example `UploadHistoryStoreTests.swift`, and name cases with `test...` descriptions. Add tests for upload naming, pull destination naming, directory handling, history persistence, lock behavior, parsing, and user-facing error formatting.

## Commit & Pull Request Guidelines

Recent history uses concise Conventional Commit-style subjects such as `feat: support directory uploads and live history`, `fix: lock upload history across processes`, and `docs: add Chinese README`. Keep commits scoped and imperative.

Pull requests should include a short summary, verification commands run, linked issues when applicable, and screenshots for visible app, Finder menu, or README changes. `main` is protected, so land changes through PRs rather than direct pushes.

## Security & Configuration Tips

Do not commit private SSH config, machine-specific logs, or release secrets. Finder history lives under `~/Library/Containers/ai.shili.AgentDrop.FinderSync/...`; use sample data in public docs. For local installs, prefer `ditto` over `cp -R` so the Finder Sync bundle remains valid.
