# Agent Drop Upload History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build issue #2: an in-app `Recent Uploads` history that reliably records Finder upload successes and failures, survives app relaunch, and lets users copy remote paths again.

**Architecture:** Keep upload execution in `AgentDropCore` and add a small JSON-backed history model/store there. The Finder Sync extension appends history entries after each upload attempt, while the SwiftUI app reads the same extension-container history file and presents a compact master/detail history UI. The first developer release path avoids App Groups, so the containing app becomes unsandboxed and reads the Finder extension container path directly.

**Tech Stack:** Swift 6.0, Swift Package Manager, XCTest, SwiftUI, AppKit/FinderSync, Foundation JSON encoding, `NSPasteboard`.

---

## File Structure

- Create `Sources/AgentDropCore/UploadHistoryEntry.swift` for the Codable history entry, status enum, payload formatting, and concise failure text helper.
- Create `Sources/AgentDropCore/UploadHistoryStore.swift` for JSON persistence, path resolution, append/read behavior, trimming, and corrupt-file recovery.
- Create `Tests/AgentDropCoreTests/UploadHistoryEntryTests.swift` for model, payload, and failure-message tests.
- Create `Tests/AgentDropCoreTests/UploadHistoryStoreTests.swift` for storage behavior.
- Modify `Sources/AgentDropFinderSync/FinderSync.swift` to append succeeded/failed history entries.
- Modify `Sources/AgentDropApp/AgentDropApp.swift` to replace the static instruction panel with a `Recent Uploads` list, details, refresh-on-activation behavior, and copy action.
- Modify `Sources/AgentDropApp/AgentDrop.entitlements` to remove app sandboxing for the containing developer-tool app.
- Modify `Tests/AgentDropCoreTests/BundlePlistTests.swift` to assert the containing app is intentionally unsandboxed while the Finder extension remains sandboxed.
- Modify `README.md` to document where upload history is stored and how to manually verify it.

## Task 1: Add Upload History Entry Model

**Files:**
- Create: `Sources/AgentDropCore/UploadHistoryEntry.swift`
- Test: `Tests/AgentDropCoreTests/UploadHistoryEntryTests.swift`

- [ ] **Step 1: Write failing model tests**

Create `Tests/AgentDropCoreTests/UploadHistoryEntryTests.swift`:

```swift
import XCTest
@testable import AgentDropCore

final class UploadHistoryEntryTests: XCTestCase {
    func testEncodesAndDecodesSucceededEntry() throws {
        let entry = UploadHistoryEntry(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            createdAt: Date(timeIntervalSince1970: 1_781_510_400),
            targetName: "x570",
            status: .succeeded,
            localFileNames: ["demo.png", "spec.pdf"],
            remoteDisplayPaths: [
                "~/.agent-inbox/2026-06-15/demo.png",
                "~/.agent-inbox/2026-06-15/spec.pdf"
            ],
            errorMessage: nil
        )

        let data = try JSONEncoder.agentDropHistory.encode(entry)
        let decoded = try JSONDecoder.agentDropHistory.decode(UploadHistoryEntry.self, from: data)

        XCTAssertEqual(decoded, entry)
    }

    func testCopyPayloadJoinsRemotePathsWithNewlines() {
        let entry = UploadHistoryEntry(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            createdAt: Date(timeIntervalSince1970: 1_781_510_400),
            targetName: "x570",
            status: .succeeded,
            localFileNames: ["demo.png", "spec.pdf"],
            remoteDisplayPaths: [
                "~/.agent-inbox/2026-06-15/demo.png",
                "~/.agent-inbox/2026-06-15/spec.pdf"
            ],
            errorMessage: nil
        )

        XCTAssertEqual(
            entry.copyPayload,
            "~/.agent-inbox/2026-06-15/demo.png\n~/.agent-inbox/2026-06-15/spec.pdf"
        )
    }

    func testFailedEntryHasNoCopyPayload() {
        let entry = UploadHistoryEntry(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            createdAt: Date(timeIntervalSince1970: 1_781_510_400),
            targetName: "x570",
            status: .failed,
            localFileNames: ["demo.png"],
            remoteDisplayPaths: [],
            errorMessage: "Upload to x570 failed. rsync failed"
        )

        XCTAssertNil(entry.copyPayload)
    }

    func testFailureMessageIsTrimmedForHistoryDisplay() {
        let longMessage = String(repeating: "x", count: 180)

        XCTAssertEqual(
            UploadHistoryEntry.shortErrorMessage(from: longMessage),
            String(repeating: "x", count: 117) + "..."
        )
    }
}
```

- [ ] **Step 2: Run model tests to verify they fail**

Run:

```bash
swift test --filter UploadHistoryEntryTests
```

Expected: FAIL because `UploadHistoryEntry`, `JSONEncoder.agentDropHistory`, and `JSONDecoder.agentDropHistory` do not exist.

- [ ] **Step 3: Add the history entry model**

Create `Sources/AgentDropCore/UploadHistoryEntry.swift`:

```swift
import Foundation

public struct UploadHistoryEntry: Codable, Equatable, Identifiable {
    public enum Status: String, Codable, Equatable {
        case succeeded
        case failed
    }

    public let id: UUID
    public let createdAt: Date
    public let targetName: String
    public let status: Status
    public let localFileNames: [String]
    public let remoteDisplayPaths: [String]
    public let errorMessage: String?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        targetName: String,
        status: Status,
        localFileNames: [String],
        remoteDisplayPaths: [String],
        errorMessage: String?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.targetName = targetName
        self.status = status
        self.localFileNames = localFileNames
        self.remoteDisplayPaths = remoteDisplayPaths
        self.errorMessage = errorMessage
    }

    public var copyPayload: String? {
        guard status == .succeeded, !remoteDisplayPaths.isEmpty else {
            return nil
        }
        return remoteDisplayPaths.joined(separator: "\n")
    }

    public static func shortErrorMessage(from message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 120 else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: 117)
        return String(trimmed[..<end]) + "..."
    }
}

public extension JSONEncoder {
    static var agentDropHistory: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

public extension JSONDecoder {
    static var agentDropHistory: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
```

- [ ] **Step 4: Run model tests to verify they pass**

Run:

```bash
swift test --filter UploadHistoryEntryTests
```

Expected: PASS.

- [ ] **Step 5: Commit the model**

```bash
git add Sources/AgentDropCore/UploadHistoryEntry.swift Tests/AgentDropCoreTests/UploadHistoryEntryTests.swift
git commit -m "feat: add upload history entry model"
```

## Task 2: Add JSON Upload History Store

**Files:**
- Create: `Sources/AgentDropCore/UploadHistoryStore.swift`
- Test: `Tests/AgentDropCoreTests/UploadHistoryStoreTests.swift`

- [ ] **Step 1: Write failing store tests**

Create `Tests/AgentDropCoreTests/UploadHistoryStoreTests.swift`:

```swift
import XCTest
@testable import AgentDropCore

final class UploadHistoryStoreTests: XCTestCase {
    func testHistoryFileURLUsesFinderExtensionContainer() {
        let home = URL(fileURLWithPath: "/Users/chris", isDirectory: true)

        let url = UploadHistoryStore.defaultHistoryFileURL(home: home)

        XCTAssertEqual(
            url.path,
            "/Users/chris/Library/Containers/ai.shili.AgentDrop.FinderSync/Data/Library/Application Support/Agent Drop/upload-history.json"
        )
    }

    func testReadingMissingHistoryReturnsEmptyList() throws {
        let root = try temporaryDirectory()
        let store = UploadHistoryStore(historyFileURL: root.appendingPathComponent("upload-history.json"))

        let entries = try store.load()

        XCTAssertEqual(entries, [])
    }

    func testAppendPersistsNewestFirst() throws {
        let root = try temporaryDirectory()
        let store = UploadHistoryStore(historyFileURL: root.appendingPathComponent("upload-history.json"))
        let older = entry(id: "11111111-1111-1111-1111-111111111111", createdAt: 100, targetName: "old")
        let newer = entry(id: "22222222-2222-2222-2222-222222222222", createdAt: 200, targetName: "new")

        try store.append(older)
        try store.append(newer)

        XCTAssertEqual(try store.load(), [newer, older])
    }

    func testAppendTrimsToMostRecentLimit() throws {
        let root = try temporaryDirectory()
        let store = UploadHistoryStore(historyFileURL: root.appendingPathComponent("upload-history.json"), limit: 3)

        try store.append(entry(id: "11111111-1111-1111-1111-111111111111", createdAt: 100, targetName: "one"))
        try store.append(entry(id: "22222222-2222-2222-2222-222222222222", createdAt: 200, targetName: "two"))
        try store.append(entry(id: "33333333-3333-3333-3333-333333333333", createdAt: 300, targetName: "three"))
        try store.append(entry(id: "44444444-4444-4444-4444-444444444444", createdAt: 400, targetName: "four"))

        XCTAssertEqual(try store.load().map(\.targetName), ["four", "three", "two"])
    }

    func testCorruptJSONIsPreservedAndHistoryResets() throws {
        let root = try temporaryDirectory()
        let historyURL = root.appendingPathComponent("upload-history.json")
        try Data("not-json".utf8).write(to: historyURL)
        let store = UploadHistoryStore(historyFileURL: historyURL)

        let loaded = try store.load()

        XCTAssertEqual(loaded, [])
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertTrue(files.contains("upload-history.json"))
        XCTAssertTrue(files.contains { $0.hasPrefix("upload-history.json.corrupt-") })
    }

    private func entry(id: String, createdAt: TimeInterval, targetName: String) -> UploadHistoryEntry {
        UploadHistoryEntry(
            id: UUID(uuidString: id)!,
            createdAt: Date(timeIntervalSince1970: createdAt),
            targetName: targetName,
            status: .succeeded,
            localFileNames: ["demo.png"],
            remoteDisplayPaths: ["~/.agent-inbox/2026-06-15/demo.png"],
            errorMessage: nil
        )
    }
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
```

- [ ] **Step 2: Run store tests to verify they fail**

Run:

```bash
swift test --filter UploadHistoryStoreTests
```

Expected: FAIL because `UploadHistoryStore` does not exist.

- [ ] **Step 3: Add the JSON store**

Create `Sources/AgentDropCore/UploadHistoryStore.swift`:

```swift
import Foundation

public final class UploadHistoryStore {
    private let historyFileURL: URL
    private let limit: Int
    private let fileManager: FileManager

    public init(
        historyFileURL: URL = UploadHistoryStore.defaultHistoryFileURL(),
        limit: Int = 100,
        fileManager: FileManager = .default
    ) {
        self.historyFileURL = historyFileURL
        self.limit = limit
        self.fileManager = fileManager
    }

    public static func defaultHistoryFileURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home
            .appendingPathComponent("Library/Containers/ai.shili.AgentDrop.FinderSync/Data/Library/Application Support/Agent Drop", isDirectory: true)
            .appendingPathComponent("upload-history.json", isDirectory: false)
    }

    public func load() throws -> [UploadHistoryEntry] {
        guard fileManager.fileExists(atPath: historyFileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: historyFileURL)
            let entries = try JSONDecoder.agentDropHistory.decode([UploadHistoryEntry].self, from: data)
            return sortedAndTrimmed(entries)
        } catch {
            try preserveCorruptHistory()
            try write([])
            return []
        }
    }

    public func append(_ entry: UploadHistoryEntry) throws {
        var entries = try load()
        entries.insert(entry, at: 0)
        try write(sortedAndTrimmed(entries))
    }

    private func sortedAndTrimmed(_ entries: [UploadHistoryEntry]) -> [UploadHistoryEntry] {
        Array(entries.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
    }

    private func write(_ entries: [UploadHistoryEntry]) throws {
        let directory = historyFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.agentDropHistory.encode(entries)
        try data.write(to: historyFileURL, options: [.atomic])
    }

    private func preserveCorruptHistory() throws {
        guard fileManager.fileExists(atPath: historyFileURL.path) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let corruptURL = historyFileURL.deletingLastPathComponent()
            .appendingPathComponent("\(historyFileURL.lastPathComponent).corrupt-\(stamp)")
        try? fileManager.removeItem(at: corruptURL)
        try fileManager.moveItem(at: historyFileURL, to: corruptURL)
    }
}
```

- [ ] **Step 4: Run store tests to verify they pass**

Run:

```bash
swift test --filter UploadHistoryStoreTests
```

Expected: PASS.

- [ ] **Step 5: Commit the store**

```bash
git add Sources/AgentDropCore/UploadHistoryStore.swift Tests/AgentDropCoreTests/UploadHistoryStoreTests.swift
git commit -m "feat: persist upload history"
```

## Task 3: Record Finder Upload History

**Files:**
- Modify: `Sources/AgentDropFinderSync/FinderSync.swift`
- Test: `Tests/AgentDropCoreTests/UploadHistoryEntryTests.swift`

- [ ] **Step 1: Add failing factory tests for Finder entries**

Append these tests to `Tests/AgentDropCoreTests/UploadHistoryEntryTests.swift`:

```swift
func testBuildsSucceededEntryFromUploadedFiles() {
    let uploaded = [
        UploadedFile(
            localURL: URL(fileURLWithPath: "/tmp/demo.png"),
            remoteDisplayPath: "~/.agent-inbox/2026-06-15/demo.png"
        )
    ]

    let entry = UploadHistoryEntry.succeeded(
        targetName: "x570",
        uploadedFiles: uploaded,
        createdAt: Date(timeIntervalSince1970: 123),
        id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    )

    XCTAssertEqual(entry.status, .succeeded)
    XCTAssertEqual(entry.targetName, "x570")
    XCTAssertEqual(entry.localFileNames, ["demo.png"])
    XCTAssertEqual(entry.remoteDisplayPaths, ["~/.agent-inbox/2026-06-15/demo.png"])
    XCTAssertNil(entry.errorMessage)
}

func testBuildsFailedEntryFromSelectedFiles() {
    let entry = UploadHistoryEntry.failed(
        targetName: "x570",
        fileURLs: [URL(fileURLWithPath: "/tmp/demo.png")],
        errorDescription: String(repeating: "x", count: 180),
        createdAt: Date(timeIntervalSince1970: 123),
        id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
    )

    XCTAssertEqual(entry.status, .failed)
    XCTAssertEqual(entry.targetName, "x570")
    XCTAssertEqual(entry.localFileNames, ["demo.png"])
    XCTAssertEqual(entry.remoteDisplayPaths, [])
    XCTAssertEqual(entry.errorMessage, String(repeating: "x", count: 117) + "...")
}
```

- [ ] **Step 2: Run entry tests to verify they fail**

Run:

```bash
swift test --filter UploadHistoryEntryTests
```

Expected: FAIL because the `succeeded` and `failed` factory methods do not exist.

- [ ] **Step 3: Add factory methods**

Add this extension to the bottom of `Sources/AgentDropCore/UploadHistoryEntry.swift`:

```swift
public extension UploadHistoryEntry {
    static func succeeded(
        targetName: String,
        uploadedFiles: [UploadedFile],
        createdAt: Date = Date(),
        id: UUID = UUID()
    ) -> UploadHistoryEntry {
        UploadHistoryEntry(
            id: id,
            createdAt: createdAt,
            targetName: targetName,
            status: .succeeded,
            localFileNames: uploadedFiles.map { $0.localURL.lastPathComponent },
            remoteDisplayPaths: uploadedFiles.map(\.remoteDisplayPath),
            errorMessage: nil
        )
    }

    static func failed(
        targetName: String,
        fileURLs: [URL],
        errorDescription: String,
        createdAt: Date = Date(),
        id: UUID = UUID()
    ) -> UploadHistoryEntry {
        UploadHistoryEntry(
            id: id,
            createdAt: createdAt,
            targetName: targetName,
            status: .failed,
            localFileNames: fileURLs.map(\.lastPathComponent),
            remoteDisplayPaths: [],
            errorMessage: shortErrorMessage(from: errorDescription)
        )
    }
}
```

- [ ] **Step 4: Run entry tests to verify they pass**

Run:

```bash
swift test --filter UploadHistoryEntryTests
```

Expected: PASS.

- [ ] **Step 5: Record history from Finder Sync**

Modify `Sources/AgentDropFinderSync/FinderSync.swift`:

1. Add a store property near `private let runner`:

```swift
private let historyStore = UploadHistoryStore()
```

2. In the success path, immediately after `let uploaded = try UploadService...`, append history:

```swift
let entry = UploadHistoryEntry.succeeded(targetName: target.name, uploadedFiles: uploaded)
Self.recordHistory(entry, store: self.historyStore)
```

3. In the catch block, before marking files failed, append a failure entry:

```swift
let entry = UploadHistoryEntry.failed(
    targetName: target.name,
    fileURLs: selection.files,
    errorDescription: String(describing: error)
)
Self.recordHistory(entry, store: self.historyStore)
```

4. Add this helper near `recordDiagnostic`:

```swift
private static func recordHistory(_ entry: UploadHistoryEntry, store: UploadHistoryStore) {
    do {
        try store.append(entry)
        recordDiagnostic("history recorded id=\(entry.id.uuidString) status=\(entry.status.rawValue)")
    } catch {
        recordDiagnostic("history failed id=\(entry.id.uuidString) error=\(String(describing: error))")
    }
}
```

- [ ] **Step 6: Run package tests**

Run:

```bash
swift test --filter UploadHistoryEntryTests
swift test --filter UploadHistoryStoreTests
```

Expected: PASS.

- [ ] **Step 7: Build app without signing**

Run:

```bash
xcodegen generate
xcodebuild -project AgentDrop.xcodeproj -scheme AgentDrop -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 8: Commit Finder history recording**

```bash
git add Sources/AgentDropCore/UploadHistoryEntry.swift Sources/AgentDropFinderSync/FinderSync.swift Tests/AgentDropCoreTests/UploadHistoryEntryTests.swift
git commit -m "feat: record Finder upload history"
```

## Task 4: Make Containing App Read Developer History Path

**Files:**
- Modify: `Sources/AgentDropApp/AgentDrop.entitlements`
- Modify: `Tests/AgentDropCoreTests/BundlePlistTests.swift`
- Test: `Tests/AgentDropCoreTests/BundlePlistTests.swift`

- [ ] **Step 1: Update entitlement tests first**

Replace `testAppEntitlementsSupportDevelopmentSigning` in `Tests/AgentDropCoreTests/BundlePlistTests.swift` with:

```swift
func testAppEntitlementsKeepContainingAppUnsandboxedForDeveloperHistoryAccess() throws {
    let entitlements = try loadPlist("Sources/AgentDropApp/AgentDrop.entitlements")

    XCTAssertNil(entitlements["com.apple.security.app-sandbox"])
    XCTAssertNil(entitlements["com.apple.security.network.client"])
}
```

Keep `testFinderExtensionEntitlementsSupportDevelopmentSigning` unchanged.

- [ ] **Step 2: Run entitlement test to verify it fails**

Run:

```bash
swift test --filter BundlePlistTests/testAppEntitlementsKeepContainingAppUnsandboxedForDeveloperHistoryAccess
```

Expected: FAIL because the app entitlement file still declares sandbox and network client entitlement.

- [ ] **Step 3: Remove containing app sandbox entitlements**

Replace `Sources/AgentDropApp/AgentDrop.entitlements` with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
```

- [ ] **Step 4: Run entitlement tests**

Run:

```bash
swift test --filter BundlePlistTests
```

Expected: PASS.

- [ ] **Step 5: Build app without signing**

Run:

```bash
xcodegen generate
xcodebuild -project AgentDrop.xcodeproj -scheme AgentDrop -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit entitlement change**

```bash
git add Sources/AgentDropApp/AgentDrop.entitlements Tests/AgentDropCoreTests/BundlePlistTests.swift
git commit -m "chore: keep Agent Drop app unsandboxed"
```

## Task 5: Replace Static App Window With Recent Uploads UI

**Files:**
- Modify: `Sources/AgentDropApp/AgentDropApp.swift`

- [ ] **Step 1: Replace app UI with history view**

Replace `Sources/AgentDropApp/AgentDropApp.swift` with:

```swift
import SwiftUI
import AppKit
import AgentDropCore

@main
struct AgentDropApp: App {
    var body: some Scene {
        WindowGroup {
            UploadHistoryView()
        }
    }
}

private struct UploadHistoryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var entries: [UploadHistoryEntry] = []
    @State private var selectedID: UploadHistoryEntry.ID?
    @State private var statusMessage: String?

    private let store = UploadHistoryStore()

    var selectedEntry: UploadHistoryEntry? {
        entries.first { $0.id == selectedID } ?? entries.first
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recent Uploads")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    Button("Refresh") {
                        loadHistory()
                    }
                }

                if entries.isEmpty {
                    ContentUnavailableView(
                        "No uploads yet",
                        systemImage: "tray",
                        description: Text("Right-click a file in Finder, choose Agent Drop, then select an SSH target.")
                    )
                } else {
                    List(selection: $selectedID) {
                        ForEach(entries) { entry in
                            UploadHistoryRow(entry: entry)
                                .tag(entry.id)
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .padding()
            .frame(minWidth: 300)
        } detail: {
            if let selectedEntry {
                UploadHistoryDetail(entry: selectedEntry, statusMessage: $statusMessage)
            } else {
                ContentUnavailableView(
                    "Select an upload",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Upload details and copyable remote paths will appear here.")
                )
            }
        }
        .frame(minWidth: 760, minHeight: 420)
        .onAppear(perform: loadHistory)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                loadHistory()
            }
        }
    }

    private func loadHistory() {
        do {
            entries = try store.load()
            if selectedID == nil || !entries.contains(where: { $0.id == selectedID }) {
                selectedID = entries.first?.id
            }
            statusMessage = nil
        } catch {
            entries = []
            selectedID = nil
            statusMessage = "Could not read upload history."
        }
    }
}

private struct UploadHistoryRow: View {
    let entry: UploadHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(entry.status == .succeeded ? "Succeeded" : "Failed", systemImage: entry.status == .succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(entry.status == .succeeded ? .green : .red)
                    .labelStyle(.iconOnly)
                Text(entry.targetName)
                    .fontWeight(.medium)
                Spacer()
                Text(entry.createdAt, style: .time)
                    .foregroundStyle(.secondary)
            }

            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }

    private var summary: String {
        let noun = entry.localFileNames.count == 1 ? "file" : "files"
        if entry.status == .succeeded {
            return "\(entry.localFileNames.count) \(noun) uploaded"
        }
        return entry.errorMessage ?? "Upload failed"
    }
}

private struct UploadHistoryDetail: View {
    let entry: UploadHistoryEntry
    @Binding var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.targetName)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(entry.createdAt, format: .dateTime.year().month().day().hour().minute().second())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let payload = entry.copyPayload {
                    Button("Copy Paths") {
                        copy(payload)
                    }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                }
            }

            LabeledContent("Status") {
                Text(entry.status == .succeeded ? "Succeeded" : "Failed")
                    .foregroundStyle(entry.status == .succeeded ? .green : .red)
            }

            if !entry.remoteDisplayPaths.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Remote Paths")
                        .font(.headline)
                    Text(entry.remoteDisplayPaths.joined(separator: "\n"))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            if let errorMessage = entry.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Error")
                        .font(.headline)
                    Text(errorMessage)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Local Files")
                    .font(.headline)
                ForEach(entry.localFileNames, id: \.self) { name in
                    Text(name)
                        .font(.system(.body, design: .monospaced))
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(24)
    }

    private func copy(_ payload: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(payload, forType: .string) {
            statusMessage = "Copied remote paths."
        } else {
            statusMessage = "Could not copy remote paths."
        }
    }
}
```

- [ ] **Step 2: Build the app without signing**

Run:

```bash
xcodegen generate
xcodebuild -project AgentDrop.xcodeproj -scheme AgentDrop -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run package tests**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 4: Commit UI**

```bash
git add Sources/AgentDropApp/AgentDropApp.swift
git commit -m "feat: show upload history in app"
```

## Task 6: Document History Verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add README history notes**

Add this section under `## Finder Extension Notes` in `README.md`. Use indented code blocks inside the Markdown section so the surrounding plan fencing is not copied into `README.md`:

```markdown
## Upload History

Agent Drop records recent Finder uploads in the Finder extension container:

    ~/Library/Containers/ai.shili.AgentDrop.FinderSync/Data/Library/Application Support/Agent Drop/upload-history.json

The app reads that file to show `Recent Uploads`. Successful rows include
remote paths that can be copied again. Failed rows include a short error.

For this developer build path, the containing app is intentionally
unsandboxed so it can read the Finder extension history file without requiring
an Apple Developer Program App Group. A later signed and notarized release can
migrate the store to an App Group container.
```

- [ ] **Step 2: Add manual verification commands**

Add this under the existing manual Finder smoke test in `README.md`. Use indented command blocks:

```markdown
After a Finder upload, verify history was written:

    HISTORY="$HOME/Library/Containers/ai.shili.AgentDrop.FinderSync/Data/Library/Application Support/Agent Drop/upload-history.json"
    test -f "$HISTORY"
    python3 -m json.tool "$HISTORY" | sed -n '1,80p'

Open `Agent Drop.app` and confirm the upload appears in `Recent Uploads`.
Select the upload, click `Copy Paths`, and verify:

    pbpaste
```

- [ ] **Step 3: Run tests**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 4: Commit docs**

```bash
git add README.md
git commit -m "docs: document upload history verification"
```

## Task 7: End-to-End Local Verification

**Files:**
- Verify existing source files only.
- Modify only if verification exposes a bug.

- [ ] **Step 1: Run full package tests**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 2: Generate and build the app**

Run:

```bash
xcodegen generate
xcodebuild -project AgentDrop.xcodeproj -scheme AgentDrop -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Build signed Debug app for local Finder verification**

Run:

```bash
xcodebuild -project AgentDrop.xcodeproj -scheme AgentDrop -configuration Debug build
```

Expected: BUILD SUCCEEDED with local development signing.

- [ ] **Step 4: Install the signed app locally**

Run:

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

Expected: Agent Drop opens and Finder restarts.

- [ ] **Step 5: Verify successful Finder upload creates history**

Run:

```bash
TEST_FILE="$HOME/Downloads/agent-drop-history-test.txt"
printf 'history smoke\n' > "$TEST_FILE"
open -R "$TEST_FILE"
```

In Finder, right-click `agent-drop-history-test.txt`, choose `Agent Drop -> <your SSH target>`.

Then run:

```bash
HISTORY="$HOME/Library/Containers/ai.shili.AgentDrop.FinderSync/Data/Library/Application Support/Agent Drop/upload-history.json"
python3 -m json.tool "$HISTORY" | sed -n '1,120p'
pbpaste
```

Expected: history contains a `succeeded` entry for the selected target, and `pbpaste` contains the remote path.

- [ ] **Step 6: Verify app shows and copies history**

Open or focus `Agent Drop.app`.

Expected:
- `Recent Uploads` shows the successful upload.
- Selecting it shows the remote path.
- Clicking `Copy Paths` updates `pbpaste` to the same remote path.

- [ ] **Step 7: Verify failed upload creates history**

Temporarily choose a target that cannot connect, or disconnect network access for a configured target, then attempt one Finder upload.

Run:

```bash
HISTORY="$HOME/Library/Containers/ai.shili.AgentDrop.FinderSync/Data/Library/Application Support/Agent Drop/upload-history.json"
python3 -m json.tool "$HISTORY" | sed -n '1,160p'
```

Expected: newest history entry has `status` set to `failed` and a concise `errorMessage`.

- [ ] **Step 8: Commit any verification fixes**

If source changes were needed:

```bash
git add Sources Tests README.md project.yml
git commit -m "fix: address upload history verification issues"
```

If no source changes were needed, do not create an empty commit.
