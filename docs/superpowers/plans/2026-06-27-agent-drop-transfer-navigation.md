# Agent Drop Transfer Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize the Agent Drop app so Transfer is the primary section, Hosts are shared transfer context, Drop/Pull are modes inside Transfer, History is secondary, and the bottom status bar stays global.

**Architecture:** Add a small testable navigation state model in `AgentDropCore`, then reshape `AgentDropApp.swift` around a window shell with app navigation, a transfer workspace, a shared hosts column, a Drop landing pane, the existing Pull form adapted to parent-owned target selection, and a global status bar. Keep transfer engines and history persistence unchanged.

**Tech Stack:** Swift 6, SwiftUI macOS, XCTest, XcodeGen, Xcode build.

---

### Task 1: Testable Navigation State

**Files:**
- Create: `Sources/AgentDropCore/TransferNavigationState.swift`
- Create: `Tests/AgentDropCoreTests/TransferNavigationStateTests.swift`

- [x] **Step 1: Write failing tests**

Cover default `Transfer` + `Drop`, pull route selection, history selection preserving transfer mode, selected target persistence, and clearing unavailable target IDs.

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --filter TransferNavigationStateTests`
Expected: compile failure for missing `TransferNavigationState`.

- [x] **Step 3: Implement minimal core model**

Add `AppSection`, `TransferMode`, and `TransferNavigationState`.

- [x] **Step 4: Run test to verify it passes**

Run: `swift test --filter TransferNavigationStateTests`
Expected: 5 tests passed.

### Task 2: Transfer-First Window Shell

**Files:**
- Modify: `Sources/AgentDropApp/AgentDropApp.swift`

- [x] **Step 1: Replace top-level tabs**

Replace the `TabView` in `TransferWindowView` with a window shell: left navigation for `Transfer` and `History`, center content, and global bottom status bar.

- [x] **Step 2: Add transfer workspace**

Add `TransferWorkspaceView` with shared host discovery, compact refresh icon, target selection list, and a `Picker` segmented control for `Drop` / `Pull from...`.

- [x] **Step 3: Adapt Pull form**

Remove the target picker from `PullFormView`. Pass `targets`, `selectedTargetID`, and target-selection helpers from the workspace. Keep clipboard prefill and download/history behavior.

- [x] **Step 4: Add Drop landing pane**

Add a lightweight `DropLandingView` that uses the selected host, opens Finder, and explains the Finder-first flow without adding a new upload engine.

### Task 3: Verification And Docs

**Files:**
- Modify: `README.md`
- Modify: `README.zh-CN.md`
- Update: `docs/assets/agent-drop-app.png`

- [x] **Step 1: Run verification**

Run: `swift test`, `xcodegen generate`, and `xcodebuild -project AgentDrop.xcodeproj -scheme AgentDrop -configuration Debug build CODE_SIGNING_ALLOWED=NO`.

- [x] **Step 2: Launch app and capture screenshot**

Build a signed Debug app, install with `ditto`, launch it, and capture the redesigned window into `docs/assets/agent-drop-app.png`.

- [x] **Step 3: Update docs**

Update English and Chinese README text so the app screenshot describes the transfer-first window rather than only recent uploads.

- [x] **Step 4: Open PR**

Push `codex/transfer-navigation-redesign`, create a PR, and include test/build/screenshot verification in the PR body.
