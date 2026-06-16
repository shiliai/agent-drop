# Agent Drop V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first macOS Agent Drop release: Finder right-click selected files, choose a discovered SSH target, upload to `~/.agent-inbox/YYYY-MM-DD/`, auto-rename conflicts, and copy final remote file paths to the Mac clipboard.

**Architecture:** Implement the upload behavior in a testable Swift core library, expose it through a Swift CLI executable, then reuse the same core from a macOS app plus Finder Sync Extension. V1 lets the extension call the shared core directly to keep the first build small; the CLI still exercises the same upload behavior and can become a separately embedded helper later. Generate the Xcode project with XcodeGen so the repo keeps source and configuration instead of checked-in `.xcodeproj` churn.

**Tech Stack:** Swift 6.3, Swift Package Manager, XCTest, XcodeGen, macOS AppKit, Finder Sync Extension, `/usr/bin/ssh`, `/usr/bin/rsync`, `/usr/bin/pbcopy`.

---

## File Structure

Create these files and keep responsibilities narrow:

- `Package.swift` - Swift package for `AgentDropCore`, `agent-drop`, and tests.
- `project.yml` - XcodeGen config for the macOS app and Finder Sync extension.
- `Sources/AgentDropCore/AgentDropVersion.swift` - package smoke-test surface.
- `Sources/AgentDropCore/FileSelection.swift` - validate local Finder/CLI inputs as regular files.
- `Sources/AgentDropCore/RemoteInboxPath.swift` - build date-based remote display and command paths.
- `Sources/AgentDropCore/ShellQuoting.swift` - quote remote shell path fragments safely.
- `Sources/AgentDropCore/RemoteNamePlanner.swift` - generate conflict-free remote filename candidates.
- `Sources/AgentDropCore/SSHConfigParser.swift` - parse stable aliases from `~/.ssh/config`.
- `Sources/AgentDropCore/ActiveSSHParser.swift` - parse active SSH command lines.
- `Sources/AgentDropCore/TargetResolver.swift` - merge and sort config and active targets.
- `Sources/AgentDropCore/CommandRunner.swift` - boundary around external processes.
- `Sources/AgentDropCore/UploadService.swift` - orchestrate directory creation, conflict checks, rsync, and clipboard updates.
- `Sources/AgentDropCore/Doctor.swift` - dependency and environment checks.
- `Sources/AgentDropCore/CLIParser.swift` - parse CLI commands without external dependencies.
- `Sources/AgentDropCLI/main.swift` - CLI entry point.
- `Sources/AgentDropApp/AgentDropApp.swift` - small container app.
- `Sources/AgentDropApp/Info.plist` - app bundle metadata.
- `Sources/AgentDropFinderSync/FinderSync.swift` - dynamic `Agent Drop -> SSH target` context menu.
- `Sources/AgentDropFinderSync/Info.plist` - Finder Sync extension metadata.
- `Tests/AgentDropCoreTests/*.swift` - focused core tests.
- `README.md` - update with build and development commands.

## Task 1: Scaffold Swift Package And XcodeGen Project

**Files:**
- Create: `Package.swift`
- Create: `project.yml`
- Create: `Sources/AgentDropCore/AgentDropVersion.swift`
- Create: `Sources/AgentDropApp/AgentDropApp.swift`
- Create: `Sources/AgentDropApp/Info.plist`
- Create: `Sources/AgentDropFinderSync/FinderSync.swift`
- Create: `Sources/AgentDropFinderSync/Info.plist`
- Test: `Tests/AgentDropCoreTests/AgentDropCoreSmokeTests.swift`

- [ ] **Step 1: Write the failing smoke test**

```swift
import XCTest
@testable import AgentDropCore

final class AgentDropCoreSmokeTests: XCTestCase {
    func testVersionConstantIsAvailable() {
        XCTAssertEqual(AgentDropVersion.current, "0.1.0")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
swift test --filter AgentDropCoreSmokeTests
```

Expected: FAIL because the Swift package and `AgentDropCore` module do not exist yet.

- [ ] **Step 3: Add the package manifest**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentDrop",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AgentDropCore", targets: ["AgentDropCore"]),
        .executable(name: "agent-drop", targets: ["AgentDropCLI"])
    ],
    targets: [
        .target(
            name: "AgentDropCore",
            path: "Sources/AgentDropCore"
        ),
        .executableTarget(
            name: "AgentDropCLI",
            dependencies: ["AgentDropCore"],
            path: "Sources/AgentDropCLI"
        ),
        .testTarget(
            name: "AgentDropCoreTests",
            dependencies: ["AgentDropCore"],
            path: "Tests/AgentDropCoreTests"
        )
    ]
)
```

- [ ] **Step 4: Add the minimal core version type**

```swift
public enum AgentDropVersion {
    public static let current = "0.1.0"
}
```

- [ ] **Step 5: Add a temporary CLI entry point**

```swift
import AgentDropCore

print("agent-drop \(AgentDropVersion.current)")
```

- [ ] **Step 6: Add XcodeGen configuration**

```yaml
name: AgentDrop
options:
  bundleIdPrefix: ai.shili
  deploymentTarget:
    macOS: "14.0"
packages:
  AgentDropPackage:
    path: .
targets:
  AgentDrop:
    type: application
    platform: macOS
    sources:
      - Sources/AgentDropApp
    dependencies:
      - target: AgentDropFinderSync
        embed: true
      - package: AgentDropPackage
        product: AgentDropCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: ai.shili.AgentDrop
        INFOPLIST_FILE: Sources/AgentDropApp/Info.plist
        CODE_SIGN_STYLE: Automatic
  AgentDropFinderSync:
    type: app-extension
    platform: macOS
    productName: AgentDropFinderSync
    sources:
      - Sources/AgentDropFinderSync
    dependencies:
      - package: AgentDropPackage
        product: AgentDropCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: ai.shili.AgentDrop.FinderSync
        INFOPLIST_FILE: Sources/AgentDropFinderSync/Info.plist
        CODE_SIGN_STYLE: Automatic
        SKIP_INSTALL: YES
```

- [ ] **Step 7: Add the minimal macOS container app**

```swift
import SwiftUI

@main
struct AgentDropApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text("Agent Drop")
                    .font(.title)
                Text("Finder extension and CLI helper for sending files to remote SSH agent inboxes.")
                    .foregroundStyle(.secondary)
                Text("Enable the Finder extension in System Settings if it is not visible in Finder.")
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(width: 520, height: 220)
        }
    }
}
```

- [ ] **Step 8: Add the app Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>Agent Drop</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleName</key>
    <string>Agent Drop</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
</dict>
</plist>
```

- [ ] **Step 9: Add a compiling Finder Sync placeholder**

```swift
import Cocoa
import FinderSync

final class FinderSync: FIFinderSync {
    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let menu = NSMenu(title: "Agent Drop")
        let item = NSMenuItem(title: "Agent Drop is starting up", action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
        return menu
    }
}
```

- [ ] **Step 10: Add the Finder Sync Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>Agent Drop Finder Extension</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleName</key>
    <string>AgentDropFinderSync</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.FinderSync</string>
        <key>NSExtensionPrincipalClass</key>
        <string>$(PRODUCT_MODULE_NAME).FinderSync</string>
    </dict>
</dict>
</plist>
```

- [ ] **Step 11: Run package tests**

Run:

```bash
swift test --filter AgentDropCoreSmokeTests
```

Expected: PASS.

- [ ] **Step 12: Generate and build the Xcode project**

Run:

```bash
xcodegen generate
xcodebuild -project AgentDrop.xcodeproj -scheme AgentDrop -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 13: Commit scaffold**

```bash
git add Package.swift project.yml Sources Tests
git commit -m "chore: scaffold Swift package and macOS project"
```

## Task 2: Local File Validation And Date Inbox Paths

**Files:**
- Create: `Sources/AgentDropCore/FileSelection.swift`
- Create: `Sources/AgentDropCore/RemoteInboxPath.swift`
- Test: `Tests/AgentDropCoreTests/FileSelectionTests.swift`
- Test: `Tests/AgentDropCoreTests/RemoteInboxPathTests.swift`

- [ ] **Step 1: Write failing file selection tests**

```swift
import XCTest
@testable import AgentDropCore

final class FileSelectionTests: XCTestCase {
    func testAcceptsRegularFiles() throws {
        let root = try temporaryDirectory()
        let file = root.appendingPathComponent("demo.png")
        FileManager.default.createFile(atPath: file.path, contents: Data("image".utf8))

        let result = FileSelection.validate([file])

        XCTAssertEqual(result.files, [file])
        XCTAssertTrue(result.rejected.isEmpty)
    }

    func testRejectsDirectories() throws {
        let root = try temporaryDirectory()
        let directory = root.appendingPathComponent("assets")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let result = FileSelection.validate([directory])

        XCTAssertTrue(result.files.isEmpty)
        XCTAssertEqual(result.rejected.map(\.url), [directory])
        XCTAssertEqual(result.rejected.map(\.reason), [.directoryUnsupported])
    }
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
```

- [ ] **Step 2: Write failing remote inbox path tests**

```swift
import XCTest
@testable import AgentDropCore

final class RemoteInboxPathTests: XCTestCase {
    func testUsesDateFolderForDisplayPath() {
        let date = Date(timeIntervalSince1970: 1_781_510_400)
        let clock = FixedClock(date: date)
        let path = RemoteInboxPath(clock: clock)

        XCTAssertEqual(path.dateFolder, "2026-06-15")
        XCTAssertEqual(path.displayDirectory, "~/.agent-inbox/2026-06-15/")
    }

    func testFormatsDisplayFilePath() {
        let path = RemoteInboxPath(clock: FixedClock(date: Date(timeIntervalSince1970: 1_781_510_400)))

        XCTAssertEqual(path.displayPath(forRemoteName: "demo.png"), "~/.agent-inbox/2026-06-15/demo.png")
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run:

```bash
swift test --filter FileSelectionTests
swift test --filter RemoteInboxPathTests
```

Expected: FAIL because `FileSelection`, `RemoteInboxPath`, and `FixedClock` do not exist.

- [ ] **Step 4: Implement file validation**

```swift
import Foundation

public enum RejectionReason: Equatable {
    case missing
    case directoryUnsupported
    case notRegularFile
}

public struct RejectedFile: Equatable {
    public let url: URL
    public let reason: RejectionReason
}

public struct FileSelectionResult: Equatable {
    public let files: [URL]
    public let rejected: [RejectedFile]
}

public enum FileSelection {
    public static func validate(_ urls: [URL], fileManager: FileManager = .default) -> FileSelectionResult {
        var files: [URL] = []
        var rejected: [RejectedFile] = []

        for url in urls {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                rejected.append(RejectedFile(url: url, reason: .missing))
                continue
            }

            if isDirectory.boolValue {
                rejected.append(RejectedFile(url: url, reason: .directoryUnsupported))
                continue
            }

            do {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey])
                if values.isRegularFile == true {
                    files.append(url)
                } else {
                    rejected.append(RejectedFile(url: url, reason: .notRegularFile))
                }
            } catch {
                rejected.append(RejectedFile(url: url, reason: .notRegularFile))
            }
        }

        return FileSelectionResult(files: files, rejected: rejected)
    }
}
```

- [ ] **Step 5: Implement date inbox paths**

```swift
import Foundation

public protocol Clock {
    var now: Date { get }
}

public struct SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
}

public struct FixedClock: Clock {
    public let date: Date
    public init(date: Date) {
        self.date = date
    }
    public var now: Date { date }
}

public struct RemoteInboxPath {
    private let clock: Clock
    private let calendar: Calendar

    public init(clock: Clock = SystemClock(), calendar: Calendar = .gregorianUTC) {
        self.clock = clock
        self.calendar = calendar
    }

    public var dateFolder: String {
        let components = calendar.dateComponents([.year, .month, .day], from: clock.now)
        return String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
    }

    public var relativeDirectory: String {
        ".agent-inbox/\(dateFolder)"
    }

    public var displayDirectory: String {
        "~/" + relativeDirectory + "/"
    }

    public func displayPath(forRemoteName remoteName: String) -> String {
        displayDirectory + remoteName
    }
}

extension Calendar {
    static var gregorianUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run:

```bash
swift test --filter FileSelectionTests
swift test --filter RemoteInboxPathTests
```

Expected: PASS.

- [ ] **Step 7: Commit file and path primitives**

```bash
git add Sources/AgentDropCore/FileSelection.swift Sources/AgentDropCore/RemoteInboxPath.swift Tests/AgentDropCoreTests
git commit -m "feat: validate selected files and date inbox paths"
```

## Task 3: Remote Shell Quoting And Filename Conflict Planning

**Files:**
- Create: `Sources/AgentDropCore/ShellQuoting.swift`
- Create: `Sources/AgentDropCore/RemoteNamePlanner.swift`
- Test: `Tests/AgentDropCoreTests/ShellQuotingTests.swift`
- Test: `Tests/AgentDropCoreTests/RemoteNamePlannerTests.swift`

- [ ] **Step 1: Write failing shell quoting tests**

```swift
import XCTest
@testable import AgentDropCore

final class ShellQuotingTests: XCTestCase {
    func testSingleQuotesRemotePathFragments() {
        XCTAssertEqual(ShellQuoting.singleQuote("demo file.png"), "'demo file.png'")
        XCTAssertEqual(ShellQuoting.singleQuote("client's note.pdf"), "'client'\"'\"'s note.pdf'")
    }

    func testBuildsHomeRelativeCommandPath() {
        let commandPath = ShellQuoting.homeRelativeCommandPath(".agent-inbox/2026-06-15/demo file.png")

        XCTAssertEqual(commandPath, "$HOME/'.agent-inbox/2026-06-15/demo file.png'")
    }
}
```

- [ ] **Step 2: Write failing remote filename tests**

```swift
import XCTest
@testable import AgentDropCore

final class RemoteNamePlannerTests: XCTestCase {
    func testCandidateNamesForFileWithExtension() {
        let planner = RemoteNamePlanner(originalName: "demo.png")

        XCTAssertEqual(Array(planner.candidates(prefixCount: 4)), ["demo.png", "demo-2.png", "demo-3.png", "demo-4.png"])
    }

    func testCandidateNamesForFileWithoutExtension() {
        let planner = RemoteNamePlanner(originalName: "README")

        XCTAssertEqual(Array(planner.candidates(prefixCount: 3)), ["README", "README-2", "README-3"])
    }

    func testCandidateNamesForDotfile() {
        let planner = RemoteNamePlanner(originalName: ".env")

        XCTAssertEqual(Array(planner.candidates(prefixCount: 3)), [".env", ".env-2", ".env-3"])
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run:

```bash
swift test --filter ShellQuotingTests
swift test --filter RemoteNamePlannerTests
```

Expected: FAIL because quoting and name planning types do not exist.

- [ ] **Step 4: Implement shell quoting**

```swift
public enum ShellQuoting {
    public static func singleQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    public static func homeRelativeCommandPath(_ relativePath: String) -> String {
        "$HOME/" + singleQuote(relativePath)
    }
}
```

- [ ] **Step 5: Implement conflict candidate generation**

```swift
public struct RemoteNamePlanner {
    private let originalName: String

    public init(originalName: String) {
        self.originalName = originalName
    }

    public func candidates(prefixCount: Int = 100) -> AnySequence<String> {
        AnySequence {
            var index = 1
            return AnyIterator {
                guard index <= prefixCount else { return nil }
                defer { index += 1 }
                return name(for: index)
            }
        }
    }

    private func name(for index: Int) -> String {
        guard index > 1 else { return originalName }

        let split = splitName(originalName)
        return split.base + "-\(index)" + split.extensionSuffix
    }

    private func splitName(_ name: String) -> (base: String, extensionSuffix: String) {
        if name.hasPrefix("."), name.dropFirst().contains(".") == false {
            return (name, "")
        }

        guard let dotIndex = name.lastIndex(of: "."), dotIndex != name.startIndex else {
            return (name, "")
        }

        let base = String(name[..<dotIndex])
        let suffix = String(name[dotIndex...])
        return (base, suffix)
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run:

```bash
swift test --filter ShellQuotingTests
swift test --filter RemoteNamePlannerTests
```

Expected: PASS.

- [ ] **Step 7: Commit remote path safety primitives**

```bash
git add Sources/AgentDropCore/ShellQuoting.swift Sources/AgentDropCore/RemoteNamePlanner.swift Tests/AgentDropCoreTests
git commit -m "feat: plan safe remote file names"
```

## Task 4: SSH Config Parsing

**Files:**
- Create: `Sources/AgentDropCore/SSHConfigParser.swift`
- Test: `Tests/AgentDropCoreTests/SSHConfigParserTests.swift`

- [ ] **Step 1: Write failing SSH config parser tests**

```swift
import XCTest
@testable import AgentDropCore

final class SSHConfigParserTests: XCTestCase {
    func testParsesSimpleHostAliases() {
        let config = """
        Host devbox
          HostName 192.168.1.20
          User chris

        Host gpu-box work-ubuntu
          User ubuntu
        """

        let targets = SSHConfigParser().parse(config)

        XCTAssertEqual(targets.map(\.name), ["devbox", "gpu-box", "work-ubuntu"])
        XCTAssertEqual(targets.map(\.source), [.config, .config, .config])
    }

    func testIgnoresWildcardHosts() {
        let config = """
        Host *
          ServerAliveInterval 30

        Host devbox
          HostName 192.168.1.20
        """

        let targets = SSHConfigParser().parse(config)

        XCTAssertEqual(targets.map(\.name), ["devbox"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter SSHConfigParserTests
```

Expected: FAIL because `SSHConfigParser` and `SSHTarget` do not exist.

- [ ] **Step 3: Implement configured SSH targets**

```swift
public enum SSHTargetSource: String, Equatable, Codable {
    case active
    case config
}

public struct SSHTarget: Equatable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let connectName: String
    public let source: SSHTargetSource

    public init(name: String, connectName: String? = nil, source: SSHTargetSource) {
        self.id = connectName ?? name
        self.name = name
        self.connectName = connectName ?? name
        self.source = source
    }
}

public struct SSHConfigParser {
    public init() {}

    public func parse(_ text: String) -> [SSHTarget] {
        var targets: [SSHTarget] = []

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("host ") else { continue }

            let names = trimmed.dropFirst(5)
                .split(whereSeparator: { $0 == " " || $0 == "\t" })
                .map(String.init)
                .filter { !$0.contains("*") && !$0.contains("?") && !$0.contains("!") }

            for name in names {
                targets.append(SSHTarget(name: name, source: .config))
            }
        }

        return targets
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
swift test --filter SSHConfigParserTests
```

Expected: PASS.

- [ ] **Step 5: Commit SSH config parsing**

```bash
git add Sources/AgentDropCore/SSHConfigParser.swift Tests/AgentDropCoreTests/SSHConfigParserTests.swift
git commit -m "feat: parse ssh config targets"
```

## Task 5: Active SSH Parsing And Target Resolution

**Files:**
- Create: `Sources/AgentDropCore/ActiveSSHParser.swift`
- Create: `Sources/AgentDropCore/TargetResolver.swift`
- Test: `Tests/AgentDropCoreTests/ActiveSSHParserTests.swift`
- Test: `Tests/AgentDropCoreTests/TargetResolverTests.swift`

- [ ] **Step 1: Write failing active SSH parser tests**

```swift
import XCTest
@testable import AgentDropCore

final class ActiveSSHParserTests: XCTestCase {
    func testParsesAliasFromSSHCommand() {
        let lines = [
            "ssh devbox",
            "ssh -A gpu-box",
            "ssh -p 2222 ubuntu@192.168.1.24"
        ]

        let targets = ActiveSSHParser().parseProcessCommands(lines)

        XCTAssertEqual(targets.map(\.connectName), ["devbox", "gpu-box", "ubuntu@192.168.1.24"])
        XCTAssertEqual(targets.map(\.source), [.active, .active, .active])
    }

    func testIgnoresSCPAndRemoteCommandsWithoutHost() {
        let lines = [
            "scp file devbox:/tmp",
            "ssh",
            "ssh -N -L 8080:localhost:80 devbox"
        ]

        let targets = ActiveSSHParser().parseProcessCommands(lines)

        XCTAssertEqual(targets.map(\.connectName), ["devbox"])
    }
}
```

- [ ] **Step 2: Write failing target resolver tests**

```swift
import XCTest
@testable import AgentDropCore

final class TargetResolverTests: XCTestCase {
    func testActiveTargetsSortBeforeConfigOnlyTargets() {
        let active = [SSHTarget(name: "devbox", source: .active)]
        let configured = [
            SSHTarget(name: "devbox", source: .config),
            SSHTarget(name: "work-ubuntu", source: .config)
        ]

        let resolved = TargetResolver.merge(active: active, configured: configured)

        XCTAssertEqual(resolved.map(\.name), ["devbox", "work-ubuntu"])
        XCTAssertEqual(resolved.map(\.source), [.active, .config])
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run:

```bash
swift test --filter ActiveSSHParserTests
swift test --filter TargetResolverTests
```

Expected: FAIL because parser and resolver do not exist.

- [ ] **Step 4: Implement active SSH command parsing**

```swift
public struct ActiveSSHParser {
    public init() {}

    public func parseProcessCommands(_ commands: [String]) -> [SSHTarget] {
        commands.compactMap(parseCommand)
    }

    private func parseCommand(_ command: String) -> SSHTarget? {
        let tokens = command.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard tokens.first == "ssh" else { return nil }

        var index = 1
        while index < tokens.count {
            let token = tokens[index]

            if ["-p", "-i", "-l", "-o", "-L", "-R", "-D", "-J"].contains(token) {
                index += 2
                continue
            }

            if token.hasPrefix("-") {
                index += 1
                continue
            }

            return SSHTarget(name: token, connectName: token, source: .active)
        }

        return nil
    }
}
```

- [ ] **Step 5: Implement target merging**

```swift
public struct TargetResolver {
    public init() {}

    public static func merge(active: [SSHTarget], configured: [SSHTarget]) -> [SSHTarget] {
        var seen = Set<String>()
        var result: [SSHTarget] = []

        for target in active {
            if seen.insert(target.connectName).inserted {
                result.append(target)
            }
        }

        for target in configured {
            if seen.insert(target.connectName).inserted {
                result.append(target)
            }
        }

        return result
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run:

```bash
swift test --filter ActiveSSHParserTests
swift test --filter TargetResolverTests
```

Expected: PASS.

- [ ] **Step 7: Commit target resolution**

```bash
git add Sources/AgentDropCore/ActiveSSHParser.swift Sources/AgentDropCore/TargetResolver.swift Tests/AgentDropCoreTests
git commit -m "feat: discover active ssh targets"
```

## Task 6: Command Runner, Doctor, And Upload Service

**Files:**
- Create: `Sources/AgentDropCore/CommandRunner.swift`
- Create: `Sources/AgentDropCore/Doctor.swift`
- Create: `Sources/AgentDropCore/UploadService.swift`
- Test: `Tests/AgentDropCoreTests/DoctorTests.swift`
- Test: `Tests/AgentDropCoreTests/ClipboardWriterTests.swift`
- Test: `Tests/AgentDropCoreTests/UploadServiceTests.swift`

- [ ] **Step 1: Write failing doctor tests**

```swift
import XCTest
@testable import AgentDropCore

final class DoctorTests: XCTestCase {
    func testReportsMissingRequiredTool() {
        let doctor = Doctor(toolLookup: { tool in tool == "ssh" ? "/usr/bin/ssh" : nil })

        let report = doctor.run()

        XCTAssertEqual(report.checks.first(where: { $0.name == "ssh" })?.status, .ok)
        XCTAssertEqual(report.checks.first(where: { $0.name == "rsync" })?.status, .missing)
        XCTAssertEqual(report.checks.first(where: { $0.name == "pbcopy" })?.status, .missing)
    }
}
```

- [ ] **Step 2: Write failing upload service tests**

```swift
import XCTest
@testable import AgentDropCore

final class UploadServiceTests: XCTestCase {
    func testUploadsFileAndCopiesFinalRemotePath() throws {
        let file = URL(fileURLWithPath: "/tmp/demo.png")
        let runner = FakeCommandRunner(results: [
            .success(stdout: "", stderr: ""),
            .failure(exitCode: 1, stdout: "", stderr: ""),
            .success(stdout: "", stderr: ""),
            .success(stdout: "", stderr: "")
        ])
        let clipboard = FakeClipboard()
        let service = UploadService(runner: runner, clipboard: clipboard, clock: FixedClock(date: Date(timeIntervalSince1970: 1_781_510_400)))

        let uploaded = try service.upload(files: [file], target: SSHTarget(name: "devbox", source: .config))

        XCTAssertEqual(uploaded.map(\.remoteDisplayPath), ["~/.agent-inbox/2026-06-15/demo.png"])
        XCTAssertEqual(clipboard.text, "~/.agent-inbox/2026-06-15/demo.png")
        XCTAssertEqual(runner.invocations.map(\.executable), ["/usr/bin/ssh", "/usr/bin/ssh", "/usr/bin/rsync"])
    }

    func testRenamesWhenRemoteFileExists() throws {
        let file = URL(fileURLWithPath: "/tmp/demo.png")
        let runner = FakeCommandRunner(results: [
            .success(stdout: "", stderr: ""),
            .success(stdout: "", stderr: ""),
            .failure(exitCode: 1, stdout: "", stderr: ""),
            .success(stdout: "", stderr: ""),
            .success(stdout: "", stderr: "")
        ])
        let clipboard = FakeClipboard()
        let service = UploadService(runner: runner, clipboard: clipboard, clock: FixedClock(date: Date(timeIntervalSince1970: 1_781_510_400)))

        let uploaded = try service.upload(files: [file], target: SSHTarget(name: "devbox", source: .config))

        XCTAssertEqual(uploaded.map(\.remoteDisplayPath), ["~/.agent-inbox/2026-06-15/demo-2.png"])
        XCTAssertEqual(clipboard.text, "~/.agent-inbox/2026-06-15/demo-2.png")
    }

    func testDoesNotWriteClipboardWhenUploadFails() {
        let file = URL(fileURLWithPath: "/tmp/demo.png")
        let runner = FakeCommandRunner(results: [
            .success(stdout: "", stderr: ""),
            .failure(exitCode: 1, stdout: "", stderr: ""),
            .failure(exitCode: 23, stdout: "", stderr: "rsync failed")
        ])
        let clipboard = FakeClipboard()
        let service = UploadService(runner: runner, clipboard: clipboard, clock: FixedClock(date: Date(timeIntervalSince1970: 1_781_510_400)))

        XCTAssertThrowsError(try service.upload(files: [file], target: SSHTarget(name: "devbox", source: .config)))
        XCTAssertNil(clipboard.text)
    }
}

private final class FakeClipboard: ClipboardWriting {
    var text: String?
    func write(_ text: String) throws {
        self.text = text
    }
}

private final class FakeCommandRunner: CommandRunning {
    var results: [CommandResult]
    var invocations: [CommandInvocation] = []

    init(results: [CommandResult]) {
        self.results = results
    }

    func run(_ invocation: CommandInvocation) throws -> CommandResult {
        invocations.append(invocation)
        return results.removeFirst()
    }
}
```

- [ ] **Step 3: Write failing clipboard writer tests**

```swift
import XCTest
@testable import AgentDropCore

final class ClipboardWriterTests: XCTestCase {
    func testWritesTextToPbcopyStandardInput() throws {
        let runner = FakeClipboardCommandRunner(result: .success(stdout: "", stderr: ""))
        let writer = PBClipboardWriter(runner: runner)

        try writer.write("~/.agent-inbox/2026-06-15/demo.png")

        XCTAssertEqual(runner.invocations, [
            CommandInvocation(
                executable: "/usr/bin/pbcopy",
                arguments: [],
                standardInput: "~/.agent-inbox/2026-06-15/demo.png"
            )
        ])
    }
}

private final class FakeClipboardCommandRunner: CommandRunning {
    let result: CommandResult
    var invocations: [CommandInvocation] = []

    init(result: CommandResult) {
        self.result = result
    }

    func run(_ invocation: CommandInvocation) throws -> CommandResult {
        invocations.append(invocation)
        return result
    }
}
```

- [ ] **Step 4: Run tests to verify they fail**

Run:

```bash
swift test --filter DoctorTests
swift test --filter ClipboardWriterTests
swift test --filter UploadServiceTests
```

Expected: FAIL because command, doctor, upload, and clipboard types do not exist.

- [ ] **Step 5: Implement command runner and clipboard boundary**

```swift
import Foundation

public struct CommandInvocation: Equatable {
    public let executable: String
    public let arguments: [String]
    public let standardInput: String?

    public init(executable: String, arguments: [String], standardInput: String? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.standardInput = standardInput
    }
}

public struct CommandResult: Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public static func success(stdout: String, stderr: String) -> CommandResult {
        CommandResult(exitCode: 0, stdout: stdout, stderr: stderr)
    }

    public static func failure(exitCode: Int32, stdout: String, stderr: String) -> CommandResult {
        CommandResult(exitCode: exitCode, stdout: stdout, stderr: stderr)
    }

    public var succeeded: Bool { exitCode == 0 }
}

public protocol CommandRunning {
    func run(_ invocation: CommandInvocation) throws -> CommandResult
}

public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(_ invocation: CommandInvocation) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = invocation.arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        if let standardInput = invocation.standardInput {
            let input = Pipe()
            process.standardInput = input
            try process.run()
            if let data = standardInput.data(using: .utf8) {
                input.fileHandleForWriting.write(data)
            }
            input.fileHandleForWriting.closeFile()
        } else {
            try process.run()
        }

        process.waitUntilExit()

        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return CommandResult(exitCode: process.terminationStatus, stdout: out, stderr: err)
    }
}

public protocol ClipboardWriting {
    func write(_ text: String) throws
}

public enum ClipboardError: Error, Equatable {
    case writeFailed(String)
}

public struct PBClipboardWriter: ClipboardWriting {
    private let runner: CommandRunning

    public init(runner: CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    public func write(_ text: String) throws {
        let result = try runner.run(CommandInvocation(executable: "/usr/bin/pbcopy", arguments: [], standardInput: text))
        guard result.succeeded else {
            throw ClipboardError.writeFailed(result.stderr)
        }
    }
}
```

- [ ] **Step 6: Implement doctor checks**

```swift
import Foundation

public enum DoctorStatus: Equatable {
    case ok
    case missing
}

public struct DoctorCheck: Equatable {
    public let name: String
    public let status: DoctorStatus
}

public struct DoctorReport: Equatable {
    public let checks: [DoctorCheck]
}

public struct Doctor {
    private let toolLookup: (String) -> String?

    public init(toolLookup: @escaping (String) -> String? = Doctor.defaultLookup) {
        self.toolLookup = toolLookup
    }

    public func run() -> DoctorReport {
        let checks = ["ssh", "rsync", "pbcopy"].map { tool in
            DoctorCheck(name: tool, status: toolLookup(tool) == nil ? .missing : .ok)
        }
        return DoctorReport(checks: checks)
    }

    private static func defaultLookup(_ tool: String) -> String? {
        ["/usr/bin/\(tool)", "/bin/\(tool)", "/opt/homebrew/bin/\(tool)"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
```

- [ ] **Step 7: Implement upload orchestration**

```swift
import Foundation

public struct UploadedFile: Equatable {
    public let localURL: URL
    public let remoteDisplayPath: String
}

public enum UploadError: Error, Equatable {
    case remoteDirectoryFailed(String)
    case noAvailableRemoteName(String)
    case rsyncFailed(String)
    case clipboardFailed
}

public final class UploadService {
    private let runner: CommandRunning
    private let clipboard: ClipboardWriting
    private let inboxPath: RemoteInboxPath

    public init(runner: CommandRunning = ProcessCommandRunner(), clipboard: ClipboardWriting? = nil, clock: Clock = SystemClock()) {
        self.runner = runner
        self.clipboard = clipboard ?? PBClipboardWriter(runner: runner)
        self.inboxPath = RemoteInboxPath(clock: clock)
    }

    public func upload(files: [URL], target: SSHTarget) throws -> [UploadedFile] {
        try createRemoteDirectory(target: target)

        var uploaded: [UploadedFile] = []

        for file in files {
            let remoteName = try chooseRemoteName(for: file.lastPathComponent, target: target)
            let relativePath = inboxPath.relativeDirectory + "/" + remoteName
            let commandPath = ShellQuoting.homeRelativeCommandPath(relativePath)

            let result = try runner.run(CommandInvocation(
                executable: "/usr/bin/rsync",
                arguments: ["-a", file.path, "\(target.connectName):\(commandPath)"]
            ))

            guard result.succeeded else {
                throw UploadError.rsyncFailed(result.stderr)
            }

            uploaded.append(UploadedFile(localURL: file, remoteDisplayPath: inboxPath.displayPath(forRemoteName: remoteName)))
        }

        do {
            try clipboard.write(uploaded.map(\.remoteDisplayPath).joined(separator: "\n"))
        } catch {
            throw UploadError.clipboardFailed
        }

        return uploaded
    }

    private func createRemoteDirectory(target: SSHTarget) throws {
        let commandPath = ShellQuoting.homeRelativeCommandPath(inboxPath.relativeDirectory)
        let result = try runner.run(CommandInvocation(
            executable: "/usr/bin/ssh",
            arguments: [target.connectName, "mkdir -p -- \(commandPath)"]
        ))

        guard result.succeeded else {
            throw UploadError.remoteDirectoryFailed(result.stderr)
        }
    }

    private func chooseRemoteName(for originalName: String, target: SSHTarget) throws -> String {
        for candidate in RemoteNamePlanner(originalName: originalName).candidates(prefixCount: 100) {
            let relativePath = inboxPath.relativeDirectory + "/" + candidate
            let commandPath = ShellQuoting.homeRelativeCommandPath(relativePath)
            let result = try runner.run(CommandInvocation(
                executable: "/usr/bin/ssh",
                arguments: [target.connectName, "test -e \(commandPath)"]
            ))

            if result.exitCode != 0 {
                return candidate
            }
        }

        throw UploadError.noAvailableRemoteName(originalName)
    }
}
```

- [ ] **Step 8: Run tests to verify they pass**

Run:

```bash
swift test --filter DoctorTests
swift test --filter ClipboardWriterTests
swift test --filter UploadServiceTests
```

Expected: PASS.

- [ ] **Step 9: Commit upload orchestration**

```bash
git add Sources/AgentDropCore/CommandRunner.swift Sources/AgentDropCore/Doctor.swift Sources/AgentDropCore/UploadService.swift Tests/AgentDropCoreTests
git commit -m "feat: upload files to remote agent inbox"
```

## Task 7: CLI Commands

**Files:**
- Create: `Sources/AgentDropCore/CLIParser.swift`
- Modify: `Sources/AgentDropCLI/main.swift`
- Test: `Tests/AgentDropCoreTests/CLIParserTests.swift`

- [ ] **Step 1: Write failing CLI parser tests**

```swift
import XCTest
@testable import AgentDropCore

final class CLIParserTests: XCTestCase {
    func testParsesTargetsCommand() throws {
        XCTAssertEqual(try CLIParser.parse(["targets"]), .targets)
    }

    func testParsesDoctorCommand() throws {
        XCTAssertEqual(try CLIParser.parse(["doctor"]), .doctor)
    }

    func testParsesSendWithExplicitTarget() throws {
        XCTAssertEqual(
            try CLIParser.parse(["send", "--target", "devbox", "/tmp/demo.png"]),
            .send(target: "devbox", paths: ["/tmp/demo.png"])
        )
    }

    func testRejectsSendWithoutFiles() {
        XCTAssertThrowsError(try CLIParser.parse(["send", "--target", "devbox"]))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter CLIParserTests
```

Expected: FAIL because the parser does not exist.

- [ ] **Step 3: Implement CLI parser**

```swift
public enum CLICommand: Equatable {
    case targets
    case doctor
    case send(target: String?, paths: [String])
}

public enum CLIParseError: Error, Equatable {
    case empty
    case unknownCommand(String)
    case missingTargetValue
    case missingFiles
}

public enum CLIParser {
    public static func parse(_ arguments: [String]) throws -> CLICommand {
        guard let command = arguments.first else { throw CLIParseError.empty }

        switch command {
        case "targets":
            return .targets
        case "doctor":
            return .doctor
        case "send":
            return try parseSend(Array(arguments.dropFirst()))
        default:
            throw CLIParseError.unknownCommand(command)
        }
    }

    private static func parseSend(_ arguments: [String]) throws -> CLICommand {
        var target: String?
        var paths: [String] = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--target" {
                let valueIndex = index + 1
                guard valueIndex < arguments.count else { throw CLIParseError.missingTargetValue }
                target = arguments[valueIndex]
                index += 2
            } else {
                paths.append(argument)
                index += 1
            }
        }

        guard paths.isEmpty == false else { throw CLIParseError.missingFiles }
        return .send(target: target, paths: paths)
    }
}
```

- [ ] **Step 4: Replace CLI entry point**

```swift
import AgentDropCore
import Darwin
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())

do {
    let command = try CLIParser.parse(arguments)
    let runner = ProcessCommandRunner()

    switch command {
    case .targets:
        let targets = discoverTargets(runner: runner)
        for target in targets {
            print("\(target.name)\t\(target.source.rawValue)")
        }

    case .doctor:
        let report = Doctor().run()
        for check in report.checks {
            print("\(check.name): \(check.status == .ok ? "ok" : "missing")")
        }

    case let .send(targetName, paths):
        let targets = discoverTargets(runner: runner)
        guard let target = resolveTarget(named: targetName, from: targets) else {
            fputs("No SSH target selected or found.\n", stderr)
            exit(2)
        }

        let urls = paths.map { URL(fileURLWithPath: $0) }
        let selection = FileSelection.validate(urls)
        guard selection.files.isEmpty == false else {
            fputs("No supported files selected.\n", stderr)
            exit(3)
        }

        let uploaded = try UploadService(runner: runner).upload(files: selection.files, target: target)
        for file in uploaded {
            print(file.remoteDisplayPath)
        }
    }
} catch {
    fputs("agent-drop: \(error)\n", stderr)
    exit(1)
}

private func discoverTargets(runner: CommandRunning) -> [SSHTarget] {
    let configText = (try? String(contentsOfFile: NSString(string: "~/.ssh/config").expandingTildeInPath)) ?? ""
    let configured = SSHConfigParser().parse(configText)

    let ps = (try? runner.run(CommandInvocation(executable: "/bin/ps", arguments: ["-axo", "command"])))?.stdout ?? ""
    let active = ActiveSSHParser().parseProcessCommands(ps.split(separator: "\n").map(String.init))

    return TargetResolver.merge(active: active, configured: configured)
}

private func resolveTarget(named name: String?, from targets: [SSHTarget]) -> SSHTarget? {
    if let name {
        return targets.first { $0.name == name || $0.connectName == name } ?? SSHTarget(name: name, connectName: name, source: .config)
    }

    if targets.count == 1 {
        return targets[0]
    }

    return nil
}
```

- [ ] **Step 5: Run parser tests**

Run:

```bash
swift test --filter CLIParserTests
```

Expected: PASS.

- [ ] **Step 6: Smoke-test CLI commands**

Run:

```bash
swift run agent-drop doctor
swift run agent-drop targets
```

Expected: `doctor` prints tool status. `targets` prints zero or more discovered targets without crashing.

- [ ] **Step 7: Commit CLI**

```bash
git add Sources/AgentDropCore/CLIParser.swift Sources/AgentDropCLI/main.swift Tests/AgentDropCoreTests/CLIParserTests.swift
git commit -m "feat: add agent-drop cli commands"
```

## Task 8: Finder Sync Dynamic Menu And Send Action

**Files:**
- Modify: `Sources/AgentDropFinderSync/FinderSync.swift`
- Modify: `Sources/AgentDropApp/AgentDropApp.swift`
- Test: Xcode build verification

- [ ] **Step 1: Replace Finder Sync placeholder with dynamic menu**

```swift
import Cocoa
import FinderSync
import AgentDropCore

final class FinderSync: FIFinderSync {
    private let runner = ProcessCommandRunner()

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: NSHomeDirectory())]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let menu = NSMenu(title: "Agent Drop")
        let root = NSMenuItem(title: "Agent Drop", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Agent Drop")

        let targets = discoverTargets()
        if targets.isEmpty {
            let empty = NSMenuItem(title: "No SSH targets found", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for target in targets {
                let suffix = target.source == .active ? "active" : "config"
                let item = NSMenuItem(title: "\(target.name)    \(suffix)", action: #selector(sendToTarget(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = target.connectName
                submenu.addItem(item)
            }
        }

        root.submenu = submenu
        menu.addItem(root)
        return menu
    }

    @objc private func sendToTarget(_ sender: NSMenuItem) {
        guard let connectName = sender.representedObject as? String else { return }
        let urls = FIFinderSyncController.default().selectedItemURLs() ?? []
        let target = SSHTarget(name: connectName, connectName: connectName, source: .config)

        DispatchQueue.global(qos: .userInitiated).async {
            let selection = FileSelection.validate(urls)
            do {
                let uploaded = try UploadService(runner: self.runner).upload(files: selection.files, target: target)
                self.notify(title: "Agent Drop", body: "Uploaded \(uploaded.count) file(s) to \(target.name). Copied remote path(s).")
            } catch {
                self.notify(title: "Agent Drop failed", body: String(describing: error))
            }
        }
    }

    private func discoverTargets() -> [SSHTarget] {
        let configPath = NSString(string: "~/.ssh/config").expandingTildeInPath
        let configText = (try? String(contentsOfFile: configPath)) ?? ""
        let configured = SSHConfigParser().parse(configText)
        let ps = (try? runner.run(CommandInvocation(executable: "/bin/ps", arguments: ["-axo", "command"])))?.stdout ?? ""
        let active = ActiveSSHParser().parseProcessCommands(ps.split(separator: "\n").map(String.init))
        return TargetResolver.merge(active: active, configured: configured)
    }

    private func notify(title: String, body: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        NSUserNotificationCenter.default.deliver(notification)
    }
}
```

- [ ] **Step 2: Update the container app copy**

```swift
import SwiftUI

@main
struct AgentDropApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 16) {
                Text("Agent Drop")
                    .font(.title)
                Text("Right-click files in Finder, choose Agent Drop, then choose an SSH target.")
                    .foregroundStyle(.secondary)
                Text("Uploaded files land in ~/.agent-inbox/YYYY-MM-DD/ on the remote machine. The final remote paths are copied to your Mac clipboard.")
                    .foregroundStyle(.secondary)
                Button("Open Extensions Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")!)
                }
            }
            .padding(24)
            .frame(width: 560, height: 260)
        }
    }
}
```

- [ ] **Step 3: Build the macOS project**

Run:

```bash
xcodegen generate
xcodebuild -project AgentDrop.xcodeproj -scheme AgentDrop -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit Finder Sync integration**

```bash
git add Sources/AgentDropFinderSync/FinderSync.swift Sources/AgentDropApp/AgentDropApp.swift project.yml
git commit -m "feat: add Finder ssh target menu"
```

## Task 9: Documentation And Verification

**Files:**
- Modify: `README.md`
- Test: full test and build commands

- [ ] **Step 1: Update README with local build commands**

Add this section:

````markdown
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

The Finder extension may need to be enabled in System Settings after building the app locally.
````

- [ ] **Step 2: Run all package tests**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 3: Generate and build the Xcode project**

Run:

```bash
xcodegen generate
xcodebuild -project AgentDrop.xcodeproj -scheme AgentDrop -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Smoke-test CLI**

Run:

```bash
swift run agent-drop doctor
swift run agent-drop targets
```

Expected: Commands complete without crashing.

- [ ] **Step 5: Commit docs and verification updates**

```bash
git add README.md
git commit -m "docs: add development workflow"
```

## Task 10: Manual End-To-End Check

**Files:**
- No planned source changes unless verification finds a defect.

- [ ] **Step 1: Select the first discovered real remote target**

Run:

```bash
TARGET="$(swift run agent-drop targets | awk 'NR==1 {print $1}')"
test -n "$TARGET" && printf 'Using target: %s\n' "$TARGET"
```

Expected: prints `Using target: <name>`. If this fails, add a usable host to `~/.ssh/config` or connect to a remote host over SSH, then rerun the command.

- [ ] **Step 2: Prepare the real remote target**

Run:

```bash
ssh "$TARGET" "mkdir -p ~/.agent-inbox/$(date +%Y-%m-%d)"
```

Expected: command exits successfully.

- [ ] **Step 3: Create a local sample file**

Run:

```bash
printf 'agent drop smoke test\n' > /tmp/agent-drop-smoke.txt
```

Expected: `/tmp/agent-drop-smoke.txt` exists.

- [ ] **Step 4: Upload with CLI**

Run:

```bash
swift run agent-drop send --target "$TARGET" /tmp/agent-drop-smoke.txt
```

Expected: CLI prints a path like `~/.agent-inbox/YYYY-MM-DD/agent-drop-smoke.txt`.

- [ ] **Step 5: Verify clipboard**

Run:

```bash
pbpaste
```

Expected: clipboard contains the same remote file path printed by the CLI.

- [ ] **Step 6: Verify remote file exists**

Run:

```bash
ssh "$TARGET" "test -f ~/.agent-inbox/$(date +%Y-%m-%d)/agent-drop-smoke.txt && echo ok"
```

Expected: prints `ok`.

- [ ] **Step 7: Verify conflict rename**

Run:

```bash
swift run agent-drop send --target "$TARGET" /tmp/agent-drop-smoke.txt
```

Expected: CLI prints a path ending in `agent-drop-smoke-2.txt`, and `pbpaste` returns that renamed path.

- [ ] **Step 8: Commit any fixes found by manual verification**

If source changes were made during verification:

```bash
git add Sources Tests README.md project.yml
git commit -m "fix: address end-to-end upload issues"
```

If no source changes were needed, do not create an empty commit.

---

## Local Development Signing And Finder Verification Notes

The Finder Sync extension requires a locally signed app/extension pair for
reliable Finder loading during development. The local development setup uses:

- Apple Development signing.
- One Team for both `AgentDrop` and `AgentDropFinderSync`.
- App sandbox plus network client entitlement on both targets.
- Finder extension read access for user-selected files and the local `~/.ssh`
  config path.

Verified local Finder path on 2026-06-16:

- Build: `xcodebuild -project AgentDrop.xcodeproj -scheme AgentDrop -configuration Debug build`.
- Installed to `~/Applications/Agent Drop.app`.
- Extension registered with `pluginkit` and enabled in System Settings.
- Finder right-click menu loaded as `Agent Drop -> x570 config`.
- Upload of `/Users/chris/Downloads/agent-drop-ui-test.png` to `x570`
  created `/home/chriswang/.agent-inbox/2026-06-16/agent-drop-ui-test.png`.
- Clipboard contained `~/.agent-inbox/2026-06-16/agent-drop-ui-test.png`.

Current feedback behavior:

- Finder menu includes a template upload icon.
- Success/failure set a short-lived Finder badge on selected files.
- The extension records upload diagnostics in
  `~/Library/Containers/ai.shili.AgentDrop.FinderSync/Data/Library/Logs/AgentDropFinderSync.log`.
- System notifications are best-effort from the Finder Sync extension and were
  not visible during local testing. Reliable in-app upload history and feedback
  is deferred to issue #2.
