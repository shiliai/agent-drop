# Agent Drop Clipboard Drop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `Drop Clipboard` action to the app Drop page that uploads valid local clipboard files or clipboard screenshots to a selected SSH host and copies the final remote path back to the Mac clipboard.

**Architecture:** Keep upload behavior inside `AgentDropCore` by adding a platform-neutral clipboard resolver plus a screenshot staging helper. Keep AppKit pasteboard adaptation and SwiftUI state inside `Sources/AgentDropApp/AgentDropApp.swift`, then call the existing `UploadService.upload(sources:target:)` and `AsyncUploadHistoryStore` paths.

**Tech Stack:** Swift 6, SwiftPM, XCTest, SwiftUI, AppKit `NSPasteboard`/`NSImage`, existing `UploadService`, `UploadSourceFile`, `FileSelection`, `AsyncUploadHistoryStore`.

---

## File Structure

- Create `Sources/AgentDropCore/ClipboardDropResolver.swift`
  - Owns platform-neutral clipboard source models, resolution, display summaries, invalid reasons, and screenshot filename formatting.
- Create `Sources/AgentDropCore/ClipboardImageStager.swift`
  - Owns writing PNG bytes into a temporary operation directory and returning `UploadSourceFile` plus cleanup.
- Create `Tests/AgentDropCoreTests/ClipboardDropResolverTests.swift`
  - Tests file URL resolution, invalid path behavior, text-only ignore behavior, image fallback, display summaries, and all-or-nothing file URL validation.
- Create `Tests/AgentDropCoreTests/ClipboardImageStagerTests.swift`
  - Tests PNG staging names, bytes, cleanup, and failure cleanup.
- Modify `Sources/AgentDropApp/AgentDropApp.swift`
  - Add app-only `NSPasteboard` adapter, Drop clipboard UI card, operation state, upload execution, history recording, and lifecycle refresh hooks.
- Optional modify `Sources/AgentDropCore/UploadFeedbackFormatter.swift`
  - Only if app upload error messages need the same user-facing shortening already used by history/errors.

Run SwiftPM tests serially in this repo; parallel `swift test` runs can contend on `.build`.

---

### Task 1: Core Clipboard Resolution

**Files:**
- Create: `Sources/AgentDropCore/ClipboardDropResolver.swift`
- Test: `Tests/AgentDropCoreTests/ClipboardDropResolverTests.swift`

- [ ] **Step 1: Write failing resolver tests**

Create `Tests/AgentDropCoreTests/ClipboardDropResolverTests.swift`:

```swift
import XCTest
@testable import AgentDropCore

final class ClipboardDropResolverTests: XCTestCase {
    func testResolvesSingleValidLocalFileURL() throws {
        let root = try makeTemporaryDirectory()
        let file = root.appendingPathComponent("demo.png")
        try Data("demo".utf8).write(to: file)

        let snapshot = ClipboardDropSnapshot(fileURLs: [file], hasImageData: false, text: nil)
        let result = ClipboardDropResolver.resolve(snapshot)

        XCTAssertEqual(result, .ready(ClipboardDropReadyItem(
            kind: .files,
            sources: [
                UploadSourceFile(
                    sourceURL: file,
                    remoteName: "demo.png",
                    localDisplayName: "demo.png",
                    isDirectory: false
                )
            ],
            summary: "demo.png ready"
        )))
    }

    func testResolvesMultipleValidLocalFileURLs() throws {
        let root = try makeTemporaryDirectory()
        let first = root.appendingPathComponent("first.png")
        let second = root.appendingPathComponent("second.txt")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)

        let snapshot = ClipboardDropSnapshot(fileURLs: [first, second], hasImageData: true, text: nil)
        let result = ClipboardDropResolver.resolve(snapshot)

        guard case let .ready(item) = result else {
            XCTFail("Expected ready result")
            return
        }
        XCTAssertEqual(item.kind, .files)
        XCTAssertEqual(item.summary, "2 local items ready")
        XCTAssertEqual(item.sources.map(\.remoteName), ["first.png", "second.txt"])
        XCTAssertEqual(item.sources.map(\.localDisplayName), ["first.png", "second.txt"])
        XCTAssertEqual(item.sources.map(\.isDirectory), [false, false])
    }

    func testResolvesValidDirectoryURL() throws {
        let root = try makeTemporaryDirectory()
        let directory = root.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let snapshot = ClipboardDropSnapshot(fileURLs: [directory], hasImageData: false, text: nil)
        let result = ClipboardDropResolver.resolve(snapshot)

        guard case let .ready(item) = result else {
            XCTFail("Expected ready result")
            return
        }
        XCTAssertEqual(item.sources, [
            UploadSourceFile(
                sourceURL: directory,
                remoteName: "assets",
                localDisplayName: "assets",
                isDirectory: true
            )
        ])
        XCTAssertEqual(item.summary, "assets ready")
    }

    func testInvalidWhenAnyLocalFileURLIsMissing() throws {
        let root = try makeTemporaryDirectory()
        let existing = root.appendingPathComponent("demo.png")
        let missing = root.appendingPathComponent("missing.png")
        try Data("demo".utf8).write(to: existing)

        let snapshot = ClipboardDropSnapshot(fileURLs: [existing, missing], hasImageData: true, text: nil)
        let result = ClipboardDropResolver.resolve(snapshot)

        XCTAssertEqual(result, .invalid(.unsupportedLocalItems(["missing.png: missing"])))
    }

    func testIgnoresPlainTextAndRemoteLookingPathText() {
        XCTAssertEqual(
            ClipboardDropResolver.resolve(ClipboardDropSnapshot(fileURLs: [], hasImageData: false, text: "~/.agent-inbox/2026-06-28/demo.png")),
            .empty
        )
        XCTAssertEqual(
            ClipboardDropResolver.resolve(ClipboardDropSnapshot(fileURLs: [], hasImageData: false, text: "devbox:/tmp/demo.png")),
            .empty
        )
        XCTAssertEqual(
            ClipboardDropResolver.resolve(ClipboardDropSnapshot(fileURLs: [], hasImageData: false, text: "/Users/chris/Desktop/demo.png")),
            .empty
        )
    }

    func testUsesImageFallbackWhenNoFileURLsExist() {
        let date = Date(timeIntervalSince1970: 1_782_641_330)
        let snapshot = ClipboardDropSnapshot(fileURLs: [], hasImageData: true, text: nil)

        let result = ClipboardDropResolver.resolve(snapshot, date: date, timeZone: TimeZone(secondsFromGMT: 8 * 3600)!)

        XCTAssertEqual(result, .ready(ClipboardDropReadyItem(
            kind: .image(ClipboardImageDrop(
                remoteName: "Screenshot 2026-06-28 at 18.08.50.png",
                localDisplayName: "Screenshot 2026-06-28 at 18.08.50.png"
            )),
            sources: [],
            summary: "Clipboard item ready"
        )))
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
```

- [ ] **Step 2: Run resolver tests to verify they fail**

Run:

```bash
swift test --filter ClipboardDropResolverTests
```

Expected: FAIL because `ClipboardDropSnapshot`, `ClipboardDropResolver`, `ClipboardDropReadyItem`, and `ClipboardImageDrop` do not exist.

- [ ] **Step 3: Implement clipboard resolver**

Create `Sources/AgentDropCore/ClipboardDropResolver.swift`:

```swift
import Foundation

public struct ClipboardDropSnapshot: Equatable, Sendable {
    public let fileURLs: [URL]
    public let hasImageData: Bool
    public let text: String?

    public init(fileURLs: [URL] = [], hasImageData: Bool = false, text: String? = nil) {
        self.fileURLs = fileURLs
        self.hasImageData = hasImageData
        self.text = text
    }
}

public struct ClipboardImageDrop: Equatable, Sendable {
    public let remoteName: String
    public let localDisplayName: String

    public init(remoteName: String, localDisplayName: String) {
        self.remoteName = remoteName
        self.localDisplayName = localDisplayName
    }
}

public enum ClipboardDropKind: Equatable, Sendable {
    case files
    case image(ClipboardImageDrop)
}

public struct ClipboardDropReadyItem: Equatable, Sendable {
    public let kind: ClipboardDropKind
    public let sources: [UploadSourceFile]
    public let summary: String

    public init(kind: ClipboardDropKind, sources: [UploadSourceFile], summary: String) {
        self.kind = kind
        self.sources = sources
        self.summary = summary
    }
}

public enum ClipboardDropInvalidReason: Equatable, Sendable {
    case unsupportedLocalItems([String])

    public var message: String {
        switch self {
        case let .unsupportedLocalItems(items):
            let joined = items.joined(separator: ", ")
            return "Clipboard contains local items that cannot be dropped: \(joined)"
        }
    }
}

public enum ClipboardDropResolution: Equatable, Sendable {
    case empty
    case invalid(ClipboardDropInvalidReason)
    case ready(ClipboardDropReadyItem)
}

public enum ClipboardDropResolver {
    public static func resolve(
        _ snapshot: ClipboardDropSnapshot,
        date: Date = Date(),
        timeZone: TimeZone = .current,
        fileManager: FileManager = .default
    ) -> ClipboardDropResolution {
        if !snapshot.fileURLs.isEmpty {
            return resolveFileURLs(snapshot.fileURLs, fileManager: fileManager)
        }

        if snapshot.hasImageData {
            let name = screenshotName(date: date, timeZone: timeZone)
            return .ready(ClipboardDropReadyItem(
                kind: .image(ClipboardImageDrop(remoteName: name, localDisplayName: name)),
                sources: [],
                summary: "Clipboard item ready"
            ))
        }

        return .empty
    }

    public static func screenshotName(date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot \(formatter.string(from: date)).png"
    }

    private static func resolveFileURLs(_ urls: [URL], fileManager: FileManager) -> ClipboardDropResolution {
        let selection = FileSelection.validate(urls, fileManager: fileManager)
        guard selection.rejected.isEmpty else {
            return .invalid(.unsupportedLocalItems(selection.rejected.map(invalidDescription)))
        }

        let sources = selection.files.map { url in
            UploadSourceFile(
                sourceURL: url,
                remoteName: url.lastPathComponent,
                localDisplayName: url.lastPathComponent,
                isDirectory: isDirectory(url, fileManager: fileManager)
            )
        }

        guard !sources.isEmpty else {
            return .empty
        }

        let summary = if sources.count == 1 {
            "\(sources[0].localDisplayName) ready"
        } else {
            "\(sources.count) local items ready"
        }

        return .ready(ClipboardDropReadyItem(kind: .files, sources: sources, summary: summary))
    }

    private static func invalidDescription(_ rejected: RejectedFile) -> String {
        "\(rejected.url.lastPathComponent): \(rejected.reason.clipboardDescription)"
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

private extension RejectionReason {
    var clipboardDescription: String {
        switch self {
        case .missing:
            return "missing"
        case .notRegularFile:
            return "not a regular file"
        }
    }
}
```

- [ ] **Step 4: Run resolver tests to verify they pass**

Run:

```bash
swift test --filter ClipboardDropResolverTests
```

Expected: PASS.

- [ ] **Step 5: Run the full core suite**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentDropCore/ClipboardDropResolver.swift Tests/AgentDropCoreTests/ClipboardDropResolverTests.swift
git commit -m "feat: resolve clipboard drop sources"
```

---

### Task 2: Screenshot Image Staging

**Files:**
- Create: `Sources/AgentDropCore/ClipboardImageStager.swift`
- Test: `Tests/AgentDropCoreTests/ClipboardImageStagerTests.swift`

- [ ] **Step 1: Write failing image staging tests**

Create `Tests/AgentDropCoreTests/ClipboardImageStagerTests.swift`:

```swift
import XCTest
@testable import AgentDropCore

final class ClipboardImageStagerTests: XCTestCase {
    func testStagesImageBytesAsUploadSource() throws {
        let root = try makeTemporaryDirectory()
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        let imageDrop = ClipboardImageDrop(
            remoteName: "Screenshot 2026-06-28 at 18.08.50.png",
            localDisplayName: "Screenshot 2026-06-28 at 18.08.50.png"
        )

        let staged = try ClipboardImageStager.stage(
            pngData: bytes,
            imageDrop: imageDrop,
            baseDirectory: root,
            directoryName: "fixed"
        )

        XCTAssertEqual(staged.directory, root.appendingPathComponent("fixed", isDirectory: true))
        XCTAssertEqual(staged.files, [
            UploadSourceFile(
                sourceURL: root.appendingPathComponent("fixed", isDirectory: true)
                    .appendingPathComponent("Screenshot 2026-06-28 at 18.08.50.png"),
                remoteName: "Screenshot 2026-06-28 at 18.08.50.png",
                localDisplayName: "Screenshot 2026-06-28 at 18.08.50.png",
                isDirectory: false
            )
        ])
        XCTAssertEqual(try Data(contentsOf: staged.files[0].sourceURL), bytes)

        try staged.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.directory.path))
    }

    func testCleansUpDirectoryWhenWriteFailsBecauseDirectoryNameIsAFile() throws {
        let root = try makeTemporaryDirectory()
        let blockingFile = root.appendingPathComponent("fixed")
        try Data("not a directory".utf8).write(to: blockingFile)
        let imageDrop = ClipboardImageDrop(remoteName: "Screenshot.png", localDisplayName: "Screenshot.png")

        XCTAssertThrowsError(try ClipboardImageStager.stage(
            pngData: Data([1, 2, 3]),
            imageDrop: imageDrop,
            baseDirectory: root,
            directoryName: "fixed"
        ))

        XCTAssertTrue(FileManager.default.fileExists(atPath: blockingFile.path))
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
```

- [ ] **Step 2: Run image staging tests to verify they fail**

Run:

```bash
swift test --filter ClipboardImageStagerTests
```

Expected: FAIL because `ClipboardImageStager` does not exist.

- [ ] **Step 3: Implement image staging**

Create `Sources/AgentDropCore/ClipboardImageStager.swift`:

```swift
import Foundation

public enum ClipboardImageStager {
    public static func stage(
        pngData: Data,
        imageDrop: ClipboardImageDrop,
        baseDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("AgentDropClipboard", isDirectory: true),
        directoryName: String = UUID().uuidString,
        fileManager: FileManager = .default
    ) throws -> StagedUpload {
        let directory = baseDirectory.appendingPathComponent(directoryName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        do {
            let destination = directory.appendingPathComponent(imageDrop.remoteName)
            try pngData.write(to: destination, options: .atomic)
            return StagedUpload(directory: directory, files: [
                UploadSourceFile(
                    sourceURL: destination,
                    remoteName: imageDrop.remoteName,
                    localDisplayName: imageDrop.localDisplayName,
                    isDirectory: false
                )
            ])
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }
}
```

- [ ] **Step 4: Run image staging tests to verify they pass**

Run:

```bash
swift test --filter ClipboardImageStagerTests
```

Expected: PASS.

- [ ] **Step 5: Run resolver tests again**

Run:

```bash
swift test --filter ClipboardDropResolverTests
```

Expected: PASS.

- [ ] **Step 6: Run the full core suite**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentDropCore/ClipboardImageStager.swift Tests/AgentDropCoreTests/ClipboardImageStagerTests.swift
git commit -m "feat: stage clipboard screenshots"
```

---

### Task 3: App Pasteboard Adapter And Drop UI

**Files:**
- Modify: `Sources/AgentDropApp/AgentDropApp.swift`
- Optional test through build only; SwiftUI private view logic is verified by core tests and manual smoke.

- [ ] **Step 1: Add pasteboard adapter types near the other app-private helpers**

In `Sources/AgentDropApp/AgentDropApp.swift`, add this app-private code near the bottom helper functions:

```swift
private struct AppClipboardSnapshot {
    let coreSnapshot: ClipboardDropSnapshot
    let imagePNGData: Data?

    static let empty = AppClipboardSnapshot(
        coreSnapshot: ClipboardDropSnapshot(),
        imagePNGData: nil
    )
}

private enum AppClipboardReader {
    static func read(_ pasteboard: NSPasteboard = .general) -> AppClipboardSnapshot {
        let fileURLs = readFileURLs(from: pasteboard)
        let imageData = fileURLs.isEmpty ? readPNGData(from: pasteboard) : nil
        let text = pasteboard.string(forType: .string)

        return AppClipboardSnapshot(
            coreSnapshot: ClipboardDropSnapshot(
                fileURLs: fileURLs,
                hasImageData: imageData != nil,
                text: text
            ),
            imagePNGData: imageData
        )
    }

    private static func readFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [NSURL] {
            return urls.map { $0 as URL }.filter(\.isFileURL)
        }

        guard let fileList = pasteboard.propertyList(forType: .init("NSFilenamesPboardType")) as? [String] else {
            return []
        }

        return fileList.map { URL(fileURLWithPath: $0) }
    }

    private static func readPNGData(from pasteboard: NSPasteboard) -> Data? {
        if let pngData = pasteboard.data(forType: .png) {
            return pngData
        }

        guard let image = NSImage(pasteboard: pasteboard) else {
            return nil
        }
        return image.pngData()
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
```

- [ ] **Step 2: Build to catch adapter compile issues**

Run:

```bash
xcodebuild -project AgentDrop.xcodeproj -scheme AgentDrop -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: PASS. If it fails because `AgentDrop.xcodeproj` is missing, run `xcodegen generate` first, then run the same build command again.

- [ ] **Step 3: Replace `DropLandingView` with clipboard state and UI**

In `Sources/AgentDropApp/AgentDropApp.swift`, replace `DropLandingView` with this implementation:

```swift
private struct DropLandingView: View {
    @Environment(\.scenePhase) private var scenePhase

    let selectedTarget: SSHTarget?
    let dependencyFeedback: DependencyFeedback?
    let dependencyFeedbackProvider = DependencyFeedbackProvider()
    let onSwitchToPull: () -> Void
    let onHistoryRecorded: () -> Void

    @State private var clipboardSnapshot = AppClipboardSnapshot.empty
    @State private var clipboardResolution = ClipboardDropResolution.empty
    @State private var status = ClipboardDropStatus.idle
    @State private var isDroppingClipboard = false
    @State private var activeClipboardOperationID: UUID?

    private let historyStore = AsyncUploadHistoryStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(description)
                    .foregroundStyle(.secondary)
            }

            if let dependencyFeedback {
                Label(dependencyFeedback.message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }

            HStack(alignment: .top, spacing: 16) {
                finderWorkflowCard
                clipboardCard
            }

            statusView

            Spacer()
        }
        .frame(maxWidth: 820, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: refreshClipboard)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshClipboard(preserveStatus: true)
            }
        }
        .onChange(of: selectedTarget?.id) { _, _ in
            if case .ready = clipboardResolution {
                status = .idle
            }
        }
    }

    private var finderWorkflowCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Finder workflow", systemImage: "folder")
                .font(.headline)

            Text("Select files or folders in Finder, right-click, choose Agent Drop, then pick the selected host.")
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()))
                } label: {
                    Label("Open Finder", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)

                Button(action: onSwitchToPull) {
                    Label("Pull instead", systemImage: "arrow.down.circle")
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55))
        }
    }

    private var clipboardCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Clipboard", systemImage: clipboardSystemImage)
                    .font(.headline)

                Spacer()

                Button(action: refreshClipboard) {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help("Check clipboard")
                .accessibilityLabel("Check clipboard")
                .disabled(isDroppingClipboard)
            }

            Text(clipboardMessage)
                .foregroundStyle(clipboardMessageStyle)
                .textSelection(.enabled)

            Button {
                startClipboardDrop()
            } label: {
                if isDroppingClipboard {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Drop Clipboard", systemImage: "doc.on.clipboard")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canDropClipboard)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(clipboardCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(clipboardCardStroke)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .idle:
            EmptyView()
        case let .progress(message):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(message)
                    .foregroundStyle(.secondary)
            }
        case let .success(paths):
            VStack(alignment: .leading, spacing: 8) {
                Label("Dropped and copied remote paths.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(paths.joined(separator: "\n"))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        case let .failure(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    private var title: String {
        guard let selectedTarget else {
            return "Drop to SSH"
        }
        return "Drop to \(selectedTarget.name)"
    }

    private var description: String {
        guard let selectedTarget else {
            return "Choose a host, then use Finder or the clipboard to send local items."
        }
        return "Send Finder selections or valid local clipboard items to \(selectedTarget.name)."
    }

    private var clipboardSystemImage: String {
        switch clipboardResolution {
        case .ready:
            return "checkmark.circle"
        case .invalid:
            return "exclamationmark.triangle"
        case .empty:
            return "doc.on.clipboard"
        }
    }

    private var clipboardMessage: String {
        switch clipboardResolution {
        case let .ready(item):
            if selectedTarget == nil {
                return "\(item.summary). Select a host first."
            }
            return item.summary
        case let .invalid(reason):
            return reason.message
        case .empty:
            return "No local clipboard item to drop."
        }
    }

    private var clipboardMessageStyle: Color {
        switch clipboardResolution {
        case .invalid:
            return .red
        case .ready:
            return .primary
        case .empty:
            return .secondary
        }
    }

    private var clipboardCardBackground: Color {
        switch clipboardResolution {
        case .ready:
            return Color.accentColor.opacity(0.10)
        case .invalid:
            return Color.red.opacity(0.07)
        case .empty:
            return Color(nsColor: .controlBackgroundColor)
        }
    }

    private var clipboardCardStroke: Color {
        switch clipboardResolution {
        case .ready:
            return Color.accentColor.opacity(0.45)
        case .invalid:
            return Color.red.opacity(0.35)
        case .empty:
            return Color(nsColor: .separatorColor).opacity(0.55)
        }
    }

    private var canDropClipboard: Bool {
        guard selectedTarget != nil, !isDroppingClipboard else {
            return false
        }
        if case .ready = clipboardResolution {
            return true
        }
        return false
    }

    private func refreshClipboard(preserveStatus: Bool = false) {
        let snapshot = AppClipboardReader.read()
        clipboardSnapshot = snapshot
        clipboardResolution = ClipboardDropResolver.resolve(snapshot.coreSnapshot)
        if !preserveStatus {
            status = .idle
        }
    }

    private func startClipboardDrop() {
        guard !isDroppingClipboard else { return }

        let currentDependencyFeedback = dependencyFeedbackProvider.feedback(for: .finderUpload)
        if let currentDependencyFeedback {
            status = .failure(currentDependencyFeedback.message)
            return
        }

        guard let target = selectedTarget else {
            status = .failure("Select an SSH target before dropping clipboard content.")
            return
        }

        let snapshot = AppClipboardReader.read()
        let resolution = ClipboardDropResolver.resolve(snapshot.coreSnapshot)
        clipboardSnapshot = snapshot
        clipboardResolution = resolution

        guard case let .ready(item) = resolution else {
            status = .failure("No local clipboard item to drop.")
            return
        }

        let operationID = UUID()
        activeClipboardOperationID = operationID
        isDroppingClipboard = true
        status = .progress("Dropping clipboard...")

        Task {
            let result = await runClipboardDrop(item: item, snapshot: snapshot, target: target)

            await MainActor.run {
                switch result {
                case let .success(uploaded):
                    status = .progress("Recording transfer...")
                    recordSucceededUpload(target: target, uploaded: uploaded, operationID: operationID) {
                        isDroppingClipboard = false
                        status = .success(uploaded.map(\.remoteDisplayPath))
                        refreshClipboardResolution()
                    }
                case let .failure(error):
                    let message = displayMessage(for: error)
                    isDroppingClipboard = false
                    status = .failure(message)
                    recordFailedUpload(target: target, item: item, message: message, operationID: operationID)
                }
            }
        }
    }

    private func runClipboardDrop(
        item: ClipboardDropReadyItem,
        snapshot: AppClipboardSnapshot,
        target: SSHTarget
    ) async -> Result<[UploadedFile], Error> {
        await Task.detached(priority: .userInitiated) {
            var stagedUpload: StagedUpload?
            do {
                let sources: [UploadSourceFile]
                switch item.kind {
                case .files:
                    sources = item.sources
                case let .image(imageDrop):
                    guard let imagePNGData = snapshot.imagePNGData else {
                        throw ClipboardDropAppError.missingImageData
                    }
                    let staged = try ClipboardImageStager.stage(pngData: imagePNGData, imageDrop: imageDrop)
                    stagedUpload = staged
                    sources = staged.files
                }

                let uploaded = try UploadService().upload(sources: sources, target: target)
                try? stagedUpload?.cleanup()
                return .success(uploaded)
            } catch {
                try? stagedUpload?.cleanup()
                return .failure(error)
            }
        }.value
    }

    private func recordSucceededUpload(
        target: SSHTarget,
        uploaded: [UploadedFile],
        operationID: UUID,
        onRecorded: @escaping () -> Void
    ) {
        let entry = UploadHistoryEntry.succeeded(targetName: target.name, uploadedFiles: uploaded)
        recordHistory(entry, operationID: operationID, onRecorded: onRecorded)
    }

    private func recordFailedUpload(
        target: SSHTarget,
        item: ClipboardDropReadyItem,
        message: String,
        operationID: UUID
    ) {
        let entry = UploadHistoryEntry(
            direction: .upload,
            targetName: target.name,
            status: .failed,
            localFileNames: item.sources.map(\.localDisplayName),
            remoteDisplayPaths: [],
            errorMessage: UploadHistoryEntry.shortErrorMessage(from: message)
        )
        recordHistory(entry, operationID: operationID, onRecorded: nil)
    }

    private func recordHistory(
        _ entry: UploadHistoryEntry,
        operationID: UUID,
        onRecorded: (() -> Void)?
    ) {
        Task {
            do {
                try await historyStore.append(entry)
                await MainActor.run {
                    guard activeClipboardOperationID == operationID else { return }
                    onHistoryRecorded()
                    onRecorded?()
                }
            } catch {
                let message = CLIErrorFormatter.message(for: error)
                await MainActor.run {
                    guard activeClipboardOperationID == operationID else { return }
                    isDroppingClipboard = false
                    status = .failure("Could not record transfer history: \(message)")
                }
            }
        }
    }

    private func refreshClipboardResolution() {
        let snapshot = AppClipboardReader.read()
        clipboardSnapshot = snapshot
        clipboardResolution = ClipboardDropResolver.resolve(snapshot.coreSnapshot)
    }

    private func displayMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return CLIErrorFormatter.message(for: error)
    }
}

private enum ClipboardDropStatus: Equatable {
    case idle
    case progress(String)
    case success([String])
    case failure(String)
}

private enum ClipboardDropAppError: LocalizedError {
    case missingImageData

    var errorDescription: String? {
        switch self {
        case .missingImageData:
            return "Clipboard image data could not be prepared."
        }
    }
}
```

- [ ] **Step 4: Update `TransferWorkspaceView` call site**

In the `.drop` case inside `TransferWorkspaceView`, update the `DropLandingView` initializer:

```swift
DropLandingView(
    selectedTarget: selectedTarget,
    dependencyFeedback: dependencyFeedback(for: .finderUpload),
    onSwitchToPull: {
        navigation.transferMode = .pull
    },
    onHistoryRecorded: onHistoryRecorded
)
```

- [ ] **Step 5: Build the app**

Run:

```bash
xcodebuild -project AgentDrop.xcodeproj -scheme AgentDrop -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: PASS. If Swift reports initializer argument ordering issues, keep the `DropLandingView` property order and initializer call exactly aligned with Swift's synthesized memberwise initializer.

- [ ] **Step 6: Run the core suite**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentDropApp/AgentDropApp.swift
git commit -m "feat: add clipboard drop UI"
```

---

### Task 4: Verification, Polish, And Manual Smoke

**Files:**
- Modify: `Sources/AgentDropApp/AgentDropApp.swift`
- Modify docs only if implementation materially changes the accepted design.

- [ ] **Step 1: Run full automated verification**

Run these commands serially:

```bash
swift test
xcodebuild -project AgentDrop.xcodeproj -scheme AgentDrop -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: both PASS.

- [ ] **Step 2: Inspect the Drop page visually**

Run a locally signed Debug build if needed:

```bash
xcodebuild -project AgentDrop.xcodeproj -scheme AgentDrop -configuration Debug build
```

Open the built app from the Xcode build output or from the existing local install flow. Verify:

- the Drop page still opens by default,
- the Finder workflow card remains visible,
- the Clipboard card is visible,
- text fits in the window at the current minimum width,
- disabled and ready states are visually distinct,
- the `Pull instead` button still switches modes.

- [ ] **Step 3: Manual smoke with text-only clipboard**

Copy remote-looking text to the Mac clipboard:

```bash
printf '%s' '~/.agent-inbox/2026-06-28/demo.png' | pbcopy
```

Open Agent Drop or refresh the Clipboard card.

Expected:

- `Drop Clipboard` is disabled,
- the Clipboard card says no local clipboard item can be dropped,
- no upload starts.

- [ ] **Step 4: Manual smoke with copied local file**

Create and copy a local test file through Finder or with AppleScript:

```bash
tmpfile="$(mktemp /tmp/agent-drop-clipboard.XXXXXX.txt)"
printf 'clipboard smoke\n' > "$tmpfile"
osascript -e 'on run argv
set the clipboard to (POSIX file (item 1 of argv))
end run' "$tmpfile"
```

Open Agent Drop or refresh the Clipboard card, select a real test host, and click `Drop Clipboard`.

Expected:

- the card shows the file name as ready,
- upload succeeds,
- the success status shows a remote `~/.agent-inbox/...` path,
- pasting in a terminal yields that remote path.

- [ ] **Step 5: Manual smoke with clipboard screenshot**

Take a screenshot directly into the clipboard using macOS screenshot shortcuts, then open Agent Drop or refresh the Clipboard card.

Expected:

- the card shows a `Screenshot YYYY-MM-DD at HH.mm.ss.png` ready item,
- selecting a host enables `Drop Clipboard`,
- upload succeeds,
- the copied remote path contains the screenshot filename or an auto-renamed variant.

- [ ] **Step 6: Reopen app after successful drop**

After a successful clipboard drop, leave the Mac clipboard unchanged and reopen or reactivate Agent Drop.

Expected:

- the clipboard now contains text remote paths,
- `Drop Clipboard` stays disabled,
- the app does not offer to upload the previous remote path.

- [ ] **Step 7: Final status check**

Run:

```bash
git status --short
```

Expected: only intentional implementation files are modified.

- [ ] **Step 8: Commit final polish if needed**

If Task 4 required code changes:

```bash
git add Sources/AgentDropApp/AgentDropApp.swift docs/superpowers/specs/2026-06-28-agent-drop-clipboard-drop-design.md
git commit -m "fix: polish clipboard drop workflow"
```

If Task 4 did not require changes, do not create an empty commit.
