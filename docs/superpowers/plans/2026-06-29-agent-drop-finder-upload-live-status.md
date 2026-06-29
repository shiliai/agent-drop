# Agent Drop Finder Upload Live Status Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show Finder-triggered uploads as live activity in the app-wide status bar and as an updating History row.

**Architecture:** Reuse the existing shared history file as the cross-process signal between Finder Sync and the app. Finder Sync writes a `running` history entry before upload work starts and `upsert`s the same entry to `succeeded` or `failed` when it finishes; the app file watcher refreshes history and derives the global status bar message from active non-stale running uploads.

**Tech Stack:** Swift 6, SwiftPM, XCTest, SwiftUI, FinderSync, XcodeGen project build.

---

## File Structure

- Modify `Sources/AgentDropCore/UploadHistoryEntry.swift` for the `running` status and `uploadStarted` factory.
- Modify `Tests/AgentDropCoreTests/UploadHistoryEntryTests.swift` for running-entry encoding, decoding, and copy behavior.
- Modify `Sources/AgentDropCore/UploadHistoryStore.swift` for `upsert(_:)`.
- Modify `Tests/AgentDropCoreTests/UploadHistoryStoreTests.swift` for replacement, insertion, ordering, and trimming behavior.
- Modify `Sources/AgentDropCore/TransferStatusSummary.swift` for a generic success status and running-upload history status derivation.
- Modify `Tests/AgentDropCoreTests/TransferStatusSummaryTests.swift` for generic success, non-stale running entries, and stale running entries.
- Modify `Sources/AgentDropFinderSync/FinderSync.swift` to write `running` before staging and update the same transfer id on success/failure.
- Modify `Sources/AgentDropApp/AgentDropApp.swift` to sync global status from history and render running/stale History rows and detail.
- Modify `README.md` to document live Finder-upload feedback and manual verification.

## Task 1: Add Running History Entries

**Files:**
- Modify: `Tests/AgentDropCoreTests/UploadHistoryEntryTests.swift`
- Modify: `Sources/AgentDropCore/UploadHistoryEntry.swift`

- [ ] **Step 1: Write failing tests for running entries**

Add these tests to `Tests/AgentDropCoreTests/UploadHistoryEntryTests.swift`:

```swift
func testEncodesAndDecodesRunningUploadEntry() throws {
    let entry = UploadHistoryEntry.uploadStarted(
        id: UUID(),
        targetName: "x570",
        fileURLs: [
            URL(fileURLWithPath: "/Users/chris/Desktop/design.pdf"),
            URL(fileURLWithPath: "/Users/chris/Desktop/screenshots")
        ],
        createdAt: Date(timeIntervalSince1970: 1_782_748_800)
    )

    let data = try JSONEncoder.agentDropHistory.encode(entry)
    let decoded = try JSONDecoder.agentDropHistory.decode(UploadHistoryEntry.self, from: data)

    XCTAssertEqual(decoded.direction, .upload)
    XCTAssertEqual(decoded.status, .running)
    XCTAssertEqual(decoded.targetName, "x570")
    XCTAssertEqual(decoded.localFileNames, ["design.pdf", "screenshots"])
    XCTAssertEqual(decoded.remoteDisplayPaths, [])
    XCTAssertEqual(decoded.localDisplayPaths, [])
    XCTAssertNil(decoded.errorMessage)
    XCTAssertEqual(decoded, entry)
}

func testRunningUploadEntryHasNoCopyPayload() {
    let entry = UploadHistoryEntry.uploadStarted(
        id: UUID(),
        targetName: "x570",
        fileURLs: [URL(fileURLWithPath: "/tmp/demo.png")],
        createdAt: Date(timeIntervalSince1970: 1_782_748_800)
    )

    XCTAssertNil(entry.copyPayload)
}
```

- [ ] **Step 2: Run the entry tests and verify they fail**

Run:

```bash
swift test --filter UploadHistoryEntryTests
```

Expected: FAIL because `UploadHistoryEntry.Status.running` and `UploadHistoryEntry.uploadStarted` do not exist.

- [ ] **Step 3: Add the running status and factory**

In `Sources/AgentDropCore/UploadHistoryEntry.swift`, extend the status enum:

```swift
public enum Status: String, Codable, Equatable, Sendable {
    case running
    case succeeded
    case failed
}
```

Add this factory inside `public extension UploadHistoryEntry`:

```swift
static func uploadStarted(
    id: UUID = UUID(),
    targetName: String,
    fileURLs: [URL],
    createdAt: Date = Date()
) -> UploadHistoryEntry {
    UploadHistoryEntry(
        id: id,
        createdAt: createdAt,
        direction: .upload,
        targetName: targetName,
        status: .running,
        localFileNames: fileURLs.map(\.lastPathComponent),
        remoteDisplayPaths: [],
        localDisplayPaths: [],
        errorMessage: nil
    )
}
```

`copyPayload` already returns nil for non-success statuses because it guards on `.succeeded`.

- [ ] **Step 4: Run the entry tests and verify they pass**

Run:

```bash
swift test --filter UploadHistoryEntryTests
```

Expected: PASS.

- [ ] **Step 5: Commit the model slice**

Run:

```bash
git add Sources/AgentDropCore/UploadHistoryEntry.swift Tests/AgentDropCoreTests/UploadHistoryEntryTests.swift
git commit -m "feat: add running transfer history entries"
```

## Task 2: Add Upsert To Upload History Store

**Files:**
- Modify: `Tests/AgentDropCoreTests/UploadHistoryStoreTests.swift`
- Modify: `Sources/AgentDropCore/UploadHistoryStore.swift`

- [ ] **Step 1: Write failing store tests**

Add these tests to `Tests/AgentDropCoreTests/UploadHistoryStoreTests.swift`:

```swift
func testUpsertReplacesEntryWithSameID() throws {
    let root = try temporaryDirectory()
    let store = UploadHistoryStore(historyFileURL: root.appendingPathComponent("upload-history.json"))
    let transferID = UUID()
    let startedAt = Date(timeIntervalSince1970: 200)
    let running = UploadHistoryEntry.uploadStarted(
        id: transferID,
        targetName: "x570",
        fileURLs: [URL(fileURLWithPath: "/tmp/demo.png")],
        createdAt: startedAt
    )
    let succeeded = UploadHistoryEntry.succeeded(
        targetName: "x570",
        uploadedFiles: [
            UploadedFile(
                localURL: URL(fileURLWithPath: "/tmp/demo.png"),
                remoteDisplayPath: "~/.agent-inbox/2026-06-29/demo.png"
            )
        ],
        createdAt: startedAt,
        id: transferID
    )

    try store.upsert(running)
    try store.upsert(succeeded)

    XCTAssertEqual(try store.load(), [succeeded])
}

func testUpsertInsertsWhenEntryIsMissing() throws {
    let root = try temporaryDirectory()
    let store = UploadHistoryStore(historyFileURL: root.appendingPathComponent("upload-history.json"))
    let succeeded = UploadHistoryEntry(
        id: UUID(),
        createdAt: Date(timeIntervalSince1970: 300),
        targetName: "x570",
        status: .succeeded,
        localFileNames: ["demo.png"],
        remoteDisplayPaths: ["~/.agent-inbox/2026-06-29/demo.png"],
        errorMessage: nil
    )

    try store.upsert(succeeded)

    XCTAssertEqual(try store.load(), [succeeded])
}

func testUpsertSortsAndTrimsAfterReplacement() throws {
    let root = try temporaryDirectory()
    let store = UploadHistoryStore(historyFileURL: root.appendingPathComponent("upload-history.json"), limit: 2)
    let oldest = UploadHistoryEntry(
        id: UUID(),
        createdAt: Date(timeIntervalSince1970: 100),
        targetName: "oldest",
        status: .succeeded,
        localFileNames: ["oldest.png"],
        remoteDisplayPaths: ["~/.agent-inbox/2026-06-29/oldest.png"],
        errorMessage: nil
    )
    let middle = UploadHistoryEntry(
        id: UUID(),
        createdAt: Date(timeIntervalSince1970: 200),
        targetName: "middle",
        status: .succeeded,
        localFileNames: ["middle.png"],
        remoteDisplayPaths: ["~/.agent-inbox/2026-06-29/middle.png"],
        errorMessage: nil
    )
    let running = UploadHistoryEntry.uploadStarted(
        id: UUID(),
        targetName: "newest",
        fileURLs: [URL(fileURLWithPath: "/tmp/demo.png")],
        createdAt: Date(timeIntervalSince1970: 300)
    )
    let completed = UploadHistoryEntry.succeeded(
        targetName: "newest",
        uploadedFiles: [
            UploadedFile(
                localURL: URL(fileURLWithPath: "/tmp/demo.png"),
                remoteDisplayPath: "~/.agent-inbox/2026-06-29/demo.png"
            )
        ],
        createdAt: Date(timeIntervalSince1970: 300),
        id: running.id
    )

    try store.append(oldest)
    try store.append(middle)
    try store.upsert(running)
    try store.upsert(completed)

    XCTAssertEqual(try store.load().map(\.targetName), ["newest", "middle"])
    XCTAssertEqual(try store.load().map(\.status), [.succeeded, .succeeded])
}
```

- [ ] **Step 2: Run the store tests and verify they fail**

Run:

```bash
swift test --filter UploadHistoryStoreTests
```

Expected: FAIL because `UploadHistoryStore.upsert(_:)` does not exist.

- [ ] **Step 3: Implement `upsert(_:)`**

In `Sources/AgentDropCore/UploadHistoryStore.swift`, add this public method next to `append(_:)`:

```swift
public func upsert(_ entry: UploadHistoryEntry) throws {
    try coordinator.sync {
        try withProcessLock {
            var entries = try loadUnlocked()
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[index] = entry
            } else {
                entries.insert(entry, at: 0)
            }
            try write(sortedAndTrimmed(entries))
        }
    }
}
```

- [ ] **Step 4: Run the store tests and verify they pass**

Run:

```bash
swift test --filter UploadHistoryStoreTests
```

Expected: PASS.

- [ ] **Step 5: Commit the store slice**

Run:

```bash
git add Sources/AgentDropCore/UploadHistoryStore.swift Tests/AgentDropCoreTests/UploadHistoryStoreTests.swift
git commit -m "feat: upsert transfer history entries"
```

## Task 3: Derive Status Bar Progress From Running History

**Files:**
- Modify: `Tests/AgentDropCoreTests/TransferStatusSummaryTests.swift`
- Modify: `Sources/AgentDropCore/TransferStatusSummary.swift`

- [ ] **Step 1: Write failing status derivation tests**

Add these tests to `Tests/AgentDropCoreTests/TransferStatusSummaryTests.swift`:

```swift
func testRunningFinderUploadHistoryProducesProgressSummary() {
    let entry = UploadHistoryEntry.uploadStarted(
        targetName: "x570",
        fileURLs: [
            URL(fileURLWithPath: "/tmp/design.pdf"),
            URL(fileURLWithPath: "/tmp/screenshots")
        ],
        createdAt: Date(timeIntervalSince1970: 1_000)
    )

    let summary = TransferStatusSummary.runningUploadHistoryStatus(
        from: [entry],
        now: Date(timeIntervalSince1970: 1_060),
        staleAfter: 1_800
    )

    XCTAssertEqual(summary, .progress("Uploading 2 files to x570..."))
}

func testNewestNonStaleRunningFinderUploadWins() {
    let older = UploadHistoryEntry.uploadStarted(
        targetName: "old",
        fileURLs: [URL(fileURLWithPath: "/tmp/old.png")],
        createdAt: Date(timeIntervalSince1970: 1_000)
    )
    let newer = UploadHistoryEntry.uploadStarted(
        targetName: "new",
        fileURLs: [URL(fileURLWithPath: "/tmp/new.png")],
        createdAt: Date(timeIntervalSince1970: 1_100)
    )

    let summary = TransferStatusSummary.runningUploadHistoryStatus(
        from: [older, newer],
        now: Date(timeIntervalSince1970: 1_120),
        staleAfter: 1_800
    )

    XCTAssertEqual(summary, .progress("Uploading 1 file to new..."))
}

func testStaleRunningFinderUploadDoesNotDriveProgressSummary() {
    let entry = UploadHistoryEntry.uploadStarted(
        targetName: "x570",
        fileURLs: [URL(fileURLWithPath: "/tmp/design.pdf")],
        createdAt: Date(timeIntervalSince1970: 1_000)
    )

    let summary = TransferStatusSummary.runningUploadHistoryStatus(
        from: [entry],
        now: Date(timeIntervalSince1970: 3_001),
        staleAfter: 1_800
    )

    XCTAssertNil(summary)
}

func testCompletedHistoryDoesNotDriveProgressSummary() {
    let entry = UploadHistoryEntry.succeeded(
        targetName: "x570",
        uploadedFiles: [
            UploadedFile(
                localURL: URL(fileURLWithPath: "/tmp/design.pdf"),
                remoteDisplayPath: "~/.agent-inbox/2026-06-29/design.pdf"
            )
        ],
        createdAt: Date(timeIntervalSince1970: 1_000)
    )

    let summary = TransferStatusSummary.runningUploadHistoryStatus(
        from: [entry],
        now: Date(timeIntervalSince1970: 1_010),
        staleAfter: 1_800
    )

    XCTAssertNil(summary)
}

func testGenericSuccessMessageIsUserVisible() {
    let summary = TransferStatusSummary.success("Uploaded 2 files to x570.")

    XCTAssertEqual(summary.statusText(lastUpdatedAt: nil), "Uploaded 2 files to x570.")
    XCTAssertEqual(summary.systemImageName, "checkmark.circle.fill")
}
```

- [ ] **Step 2: Run the status tests and verify they fail**

Run:

```bash
swift test --filter TransferStatusSummaryTests
```

Expected: FAIL because `TransferStatusSummary.success` and `TransferStatusSummary.runningUploadHistoryStatus(from:now:staleAfter:)` do not exist.

- [ ] **Step 3: Add a generic success status**

In `Sources/AgentDropCore/TransferStatusSummary.swift`, add a new enum case:

```swift
case success(String)
```

Update `systemImageName`:

```swift
case .success:
    return "checkmark.circle.fill"
```

Update `statusText(lastUpdatedAt:timeZone:)`:

```swift
case let .success(message):
    return message
```

This generic success state is for history-derived Finder uploads where the app cannot know whether Finder's clipboard write succeeded. Existing clipboard-drop code should keep using `.uploadSuccess(fileCount:targetName:copiedPaths:)`.

- [ ] **Step 4: Implement the history status helper**

In `Sources/AgentDropCore/TransferStatusSummary.swift`, add this extension after the enum:

```swift
public extension TransferStatusSummary {
    static let defaultRunningHistoryStaleInterval: TimeInterval = 30 * 60

    static func runningUploadHistoryStatus(
        from entries: [UploadHistoryEntry],
        now: Date = Date(),
        staleAfter: TimeInterval = defaultRunningHistoryStaleInterval
    ) -> TransferStatusSummary? {
        guard let entry = entries
            .filter({ $0.direction == .upload && $0.status == .running })
            .sorted(by: { $0.createdAt > $1.createdAt })
            .first(where: { now.timeIntervalSince($0.createdAt) <= staleAfter })
        else {
            return nil
        }

        let fileCount = entry.localFileNames.count
        let noun = fileCount == 1 ? "file" : "files"
        return .progress("Uploading \(fileCount) \(noun) to \(entry.targetName)...")
    }
}
```

- [ ] **Step 5: Run the status tests and verify they pass**

Run:

```bash
swift test --filter TransferStatusSummaryTests
```

Expected: PASS.

- [ ] **Step 6: Commit the status derivation slice**

Run:

```bash
git add Sources/AgentDropCore/TransferStatusSummary.swift Tests/AgentDropCoreTests/TransferStatusSummaryTests.swift
git commit -m "feat: derive live status from transfer history"
```

## Task 4: Surface Running Entries In The App

**Files:**
- Modify: `Sources/AgentDropApp/AgentDropApp.swift`

- [ ] **Step 1: Add app state for Finder-history status ownership**

In the main app view state area of `Sources/AgentDropApp/AgentDropApp.swift`, add:

```swift
@State private var activeFinderUploadID: UploadHistoryEntry.ID?
@State private var isShowingFinderUploadStatus = false
```

These flags prevent history refreshes from wiping out clipboard-drop or pull status messages that were not produced by Finder history.

- [ ] **Step 2: Sync status after successful history loads**

In `loadHistory()`, after:

```swift
historyEntries = loadedEntries
```

add:

```swift
syncFinderUploadStatus(from: loadedEntries)
```

Do not call this on history-load failure; the existing failure path should keep showing `History unavailable`.

- [ ] **Step 3: Add the Finder-history status sync helper**

Add this method near `loadHistory()`:

```swift
private func syncFinderUploadStatus(from entries: [UploadHistoryEntry], now: Date = Date()) {
    if let runningSummary = TransferStatusSummary.runningUploadHistoryStatus(from: entries, now: now),
       let runningEntry = entries
        .filter({ $0.direction == .upload && $0.status == .running })
        .sorted(by: { $0.createdAt > $1.createdAt })
        .first(where: { now.timeIntervalSince($0.createdAt) <= TransferStatusSummary.defaultRunningHistoryStaleInterval }) {
        activeFinderUploadID = runningEntry.id
        isShowingFinderUploadStatus = true
        transferStatusSummary = runningSummary
        return
    }

    guard isShowingFinderUploadStatus else {
        return
    }

    if let activeFinderUploadID,
       let completedEntry = entries.first(where: { $0.id == activeFinderUploadID }) {
        switch completedEntry.status {
        case .succeeded:
            let fileCount = completedEntry.localFileNames.count
            let noun = fileCount == 1 ? "file" : "files"
            transferStatusSummary = .success("Uploaded \(fileCount) \(noun) to \(completedEntry.targetName).")
        case .failed:
            transferStatusSummary = .failure(
                completedEntry.errorMessage ?? "Upload to \(completedEntry.targetName) failed."
            )
        case .running:
            transferStatusSummary = .idle
        }
    } else {
        transferStatusSummary = .idle
    }

    self.activeFinderUploadID = nil
    isShowingFinderUploadStatus = false
}
```

- [ ] **Step 4: Update History row status rendering**

In `UploadHistoryRow`, replace the hard-coded succeeded/failed `Label` with helper properties:

```swift
Label(statusTitle, systemImage: statusImageName)
    .foregroundStyle(statusColor)
    .labelStyle(.iconOnly)
```

Add these computed properties inside `UploadHistoryRow`:

```swift
private var statusTitle: String {
    switch entry.status {
    case .running:
        return isStaleRunning ? "Status Unknown" : "Uploading"
    case .succeeded:
        return "Succeeded"
    case .failed:
        return "Failed"
    }
}

private var statusImageName: String {
    switch entry.status {
    case .running:
        return isStaleRunning ? "questionmark.circle.fill" : "arrow.up.circle.fill"
    case .succeeded:
        return "checkmark.circle.fill"
    case .failed:
        return "xmark.circle.fill"
    }
}

private var statusColor: Color {
    switch entry.status {
    case .running:
        return isStaleRunning ? .orange : .blue
    case .succeeded:
        return .green
    case .failed:
        return .red
    }
}

private var isStaleRunning: Bool {
    entry.status == .running
        && Date().timeIntervalSince(entry.createdAt) > TransferStatusSummary.defaultRunningHistoryStaleInterval
}
```

Replace the `summary` implementation with:

```swift
private var summary: String {
    let noun = entry.localFileNames.count == 1 ? "file" : "files"
    switch entry.status {
    case .running:
        if isStaleRunning {
            return "Upload status unknown"
        }
        return "\(entry.localFileNames.count) \(noun) uploading"
    case .succeeded:
        return "\(entry.localFileNames.count) \(noun) \(entry.direction == .download ? "downloaded" : "uploaded")"
    case .failed:
        return entry.errorMessage ?? "\(entry.direction == .download ? "Download" : "Upload") failed"
    }
}
```

- [ ] **Step 5: Update History detail status rendering**

In `UploadHistoryDetail`, replace:

```swift
Text(entry.status == .succeeded ? "Succeeded" : "Failed")
    .foregroundStyle(entry.status == .succeeded ? .green : .red)
```

with:

```swift
Text(statusText)
    .foregroundStyle(statusColor)
```

Add these computed properties inside `UploadHistoryDetail`:

```swift
private var statusText: String {
    switch entry.status {
    case .running:
        return isStaleRunning ? "Status Unknown" : "Uploading"
    case .succeeded:
        return "Succeeded"
    case .failed:
        return "Failed"
    }
}

private var statusColor: Color {
    switch entry.status {
    case .running:
        return isStaleRunning ? .orange : .blue
    case .succeeded:
        return .green
    case .failed:
        return .red
    }
}

private var isStaleRunning: Bool {
    entry.status == .running
        && Date().timeIntervalSince(entry.createdAt) > TransferStatusSummary.defaultRunningHistoryStaleInterval
}
```

After the remote paths block, add:

```swift
if entry.status == .running && entry.remoteDisplayPaths.isEmpty {
    Text(isStaleRunning ? "The upload did not finish cleanly." : "Remote paths will appear after upload succeeds.")
        .foregroundStyle(.secondary)
}
```

- [ ] **Step 6: Update status bar success coloring**

In `UploadHistoryStatusBar.statusColor`, add the `.success` case:

```swift
case .success:
    return .green
```

The switch should still keep `.uploadSuccess` separate so clipboard-drop can show orange when clipboard copy fails.

- [ ] **Step 7: Build the app target**

Run:

```bash
xcodebuild -project AgentDrop.xcodeproj -scheme AgentDrop -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: PASS. If `AgentDrop.xcodeproj` is missing, run `xcodegen generate` first, then rerun the build command.

- [ ] **Step 8: Commit the app UI slice**

Run:

```bash
git add Sources/AgentDropApp/AgentDropApp.swift
git commit -m "feat: show finder upload status in app"
```

## Task 5: Write Running And Final Entries From Finder Sync

**Files:**
- Modify: `Sources/AgentDropFinderSync/FinderSync.swift`

- [ ] **Step 1: Add an upsert history helper**

In `Sources/AgentDropFinderSync/FinderSync.swift`, keep `recordHistory` for older append callers if useful, and add:

```swift
private static func upsertHistory(_ entry: UploadHistoryEntry, store: UploadHistoryStore) {
    do {
        try store.upsert(entry)
        recordDiagnostic("history upserted id=\(entry.id.uuidString) status=\(entry.status.rawValue)")
    } catch {
        recordDiagnostic("history upsert failed id=\(entry.id.uuidString) error=\(String(describing: error))")
    }
}
```

- [ ] **Step 2: Create one transfer id and start time per valid upload**

Inside `sendToTarget(_:)`, after `let target = SSHTarget(...)` and before the `do` block, add:

```swift
let transferID = UUID()
let startedAt = Date()
let startedEntry = UploadHistoryEntry.uploadStarted(
    id: transferID,
    targetName: target.name,
    fileURLs: selection.files,
    createdAt: startedAt
)
Self.upsertHistory(startedEntry, store: self.historyStore)
```

This is after dependency and selection validation, so rejected menu actions do not create running rows.

- [ ] **Step 3: Upsert the final success entry with the same id**

Replace the success history creation:

```swift
let entry = UploadHistoryEntry.succeeded(targetName: target.name, uploadedFiles: uploaded)
Self.recordHistory(entry, store: self.historyStore)
```

with:

```swift
let entry = UploadHistoryEntry.succeeded(
    targetName: target.name,
    uploadedFiles: uploaded,
    createdAt: startedAt,
    id: transferID
)
Self.upsertHistory(entry, store: self.historyStore)
```

- [ ] **Step 4: Upsert the final failure entry with the same id**

Replace the failure history creation:

```swift
let entry = UploadHistoryEntry.failed(
    targetName: target.name,
    fileURLs: selection.files,
    errorDescription: String(describing: error)
)
Self.recordHistory(entry, store: self.historyStore)
```

with:

```swift
let entry = UploadHistoryEntry.failed(
    targetName: target.name,
    fileURLs: selection.files,
    errorDescription: String(describing: error),
    createdAt: startedAt,
    id: transferID
)
Self.upsertHistory(entry, store: self.historyStore)
```

- [ ] **Step 5: Build the app and extension**

Run:

```bash
xcodebuild -project AgentDrop.xcodeproj -scheme AgentDrop -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: PASS.

- [ ] **Step 6: Commit the Finder Sync slice**

Run:

```bash
git add Sources/AgentDropFinderSync/FinderSync.swift
git commit -m "feat: record live finder upload history"
```

## Task 6: Document And Verify

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the README feedback notes**

In `README.md`, update the Finder extension and Transfer History sections to mention:

```markdown
- While a Finder upload is running, Agent Drop writes a live history row and
  the app status bar shows the active upload from any section.
- If the extension cannot finish updating a running row, old running rows are
  shown as status unknown instead of staying active forever.
```

Keep the existing history path and manual smoke-test commands.

- [ ] **Step 2: Run the full SwiftPM test suite serially**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 3: Run the no-signing Xcode build**

Run:

```bash
xcodebuild -project AgentDrop.xcodeproj -scheme AgentDrop -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: PASS.

- [ ] **Step 4: Review the diff**

Run:

```bash
git diff --check
git status --short
```

Expected: `git diff --check` exits 0. `git status --short` shows only the intended files for this feature.

- [ ] **Step 5: Commit the documentation and verification slice**

Run:

```bash
git add README.md
git commit -m "docs: document finder upload live status"
```

## Manual Verification Checklist

Run this after the implementation is built with local signing and installed for Finder Sync testing:

- [ ] Right-click a small file in Finder, choose `Agent Drop -> <target>`, and immediately open Agent Drop on `Transfer`; the bottom status bar shows `Uploading 1 file to <target>...`.
- [ ] Repeat with a directory or multiple files; the status bar pluralizes `files`.
- [ ] Open `History` while the upload is still running; the newest row shows an upload-in-progress state and local file names.
- [ ] Let the upload succeed; the same History row becomes `Succeeded`, remote paths appear, and `Copy Paths` works.
- [ ] Force an upload failure with an invalid target or unreachable host after selection validation; the same History row becomes `Failed` with a short error.
- [ ] Confirm Finder badges, notifications, clipboard copy, and `AgentDropFinderSync.log` diagnostics still work.

## Final Verification

Before claiming completion, run:

```bash
swift test
xcodebuild -project AgentDrop.xcodeproj -scheme AgentDrop -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Both commands must pass fresh in the current checkout.
