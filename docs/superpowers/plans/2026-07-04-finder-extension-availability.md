# Finder Extension Availability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Finder right-click availability understandable in the app and make the Finder Sync menu available on mounted volumes such as SMB shares under `/Volumes`.

**Architecture:** Add a tested `FinderExtensionAvailability` boundary in `AgentDropCore` that parses `pluginkit` output and runs the status command through the existing command runner. Update `FinderSyncDirectoryScope` to include `/Volumes`, then render a non-blocking setup notice in `DropLandingView` when the extension is disabled, missing, or status cannot be checked.

**Tech Stack:** Swift 6, SwiftPM, XCTest, SwiftUI, FinderSync, AppKit, `pluginkit`.

## Global Constraints

- Finder extension bundle id is exactly `ai.shili.AgentDrop.FinderSync`.
- Finder Sync extension point is exactly `com.apple.FinderSync`.
- Detection command is exactly `/usr/bin/pluginkit -m -A -p com.apple.FinderSync`.
- Do not automatically enable the extension with `pluginkit -e use`.
- The setup notice must not block clipboard upload, pull, or history workflows.
- Include `/Volumes` in Finder Sync monitored directories.
- Keep shell interaction isolated through the existing command runner pattern.

---

### Task 1: Core Finder Extension Availability And Volume Scope

**Files:**
- Create: `Sources/AgentDropCore/FinderExtensionAvailability.swift`
- Modify: `Sources/AgentDropCore/FinderSyncDirectoryScope.swift`
- Modify: `Tests/AgentDropCoreTests/FinderSyncDirectoryScopeTests.swift`
- Create: `Tests/AgentDropCoreTests/FinderExtensionAvailabilityTests.swift`

**Interfaces:**
- Produces: `public enum FinderExtensionAvailabilityStatus: Equatable, Sendable`
- Produces: `public struct FinderExtensionAvailability: Equatable, Sendable`
- Produces: `public enum FinderExtensionAvailabilityChecker`
- Produces: `public static func parse(pluginkitOutput: String, bundleIdentifier: String = FinderExtensionAvailability.bundleIdentifier) -> FinderExtensionAvailability`
- Produces: `public static func check(runner: CommandRunning = ProcessCommandRunner()) -> FinderExtensionAvailability`
- Produces: `FinderSyncDirectoryScope.monitoredDirectories(home:)` includes `/Volumes`.

- [ ] **Step 1: Write failing Finder Sync scope test**

In `Tests/AgentDropCoreTests/FinderSyncDirectoryScopeTests.swift`, add:

```swift
    func testIncludesVolumesForMountedNetworkAndExternalVolumes() {
        let home = URL(fileURLWithPath: "/Users/chris", isDirectory: true)

        let paths = FinderSyncDirectoryScope.monitoredDirectories(home: home).map(\.path)

        XCTAssertTrue(paths.contains("/Volumes"))
    }
```

- [ ] **Step 2: Run scope test to verify it fails**

Run: `swift test --filter FinderSyncDirectoryScopeTests/testIncludesVolumesForMountedNetworkAndExternalVolumes`

Expected: FAIL because `/Volumes` is not currently included.

- [ ] **Step 3: Add failing availability parser and checker tests**

Create `Tests/AgentDropCoreTests/FinderExtensionAvailabilityTests.swift`:

```swift
import XCTest
@testable import AgentDropCore

final class FinderExtensionAvailabilityTests: XCTestCase {
    func testParsesEnabledFinderExtensionFromPluginkitOutput() {
        let output = """
        +    com.synology.SynologyDrive.FinderHelper.FinderSync(1.0)
             com.microsoft.OneDrive-mac.FinderSync(26.084.0504)
        +    ai.shili.AgentDrop.FinderSync(0.2.4)
        """

        let availability = FinderExtensionAvailability.parse(pluginkitOutput: output)

        XCTAssertEqual(availability.status, .enabled)
        XCTAssertEqual(availability.bundleIdentifier, "ai.shili.AgentDrop.FinderSync")
    }

    func testParsesRegisteredButDisabledFinderExtensionFromPluginkitOutput() {
        let output = """
             ai.shili.AgentDrop.FinderSync(0.2.4)
        +    com.synology.SynologyDrive.FinderHelper.FinderSync(1.0)
        """

        let availability = FinderExtensionAvailability.parse(pluginkitOutput: output)

        XCTAssertEqual(availability.status, .disabled)
    }

    func testParsesMissingFinderExtensionFromPluginkitOutput() {
        let output = """
        +    com.synology.SynologyDrive.FinderHelper.FinderSync(1.0)
             com.microsoft.OneDrive-mac.FinderSync(26.084.0504)
        """

        let availability = FinderExtensionAvailability.parse(pluginkitOutput: output)

        XCTAssertEqual(availability.status, .notRegistered)
    }

    func testCheckReturnsUnknownWhenPluginkitCommandFails() {
        let runner = StubCommandRunner(result: .failure(CommandError.nonZeroExit(status: 1, stderr: "pluginkit failed")))

        let availability = FinderExtensionAvailabilityChecker.check(runner: runner)

        XCTAssertEqual(availability.status, .unknown("pluginkit failed"))
        XCTAssertEqual(runner.invocations, [
            CommandInvocation(
                executable: "/usr/bin/pluginkit",
                arguments: ["-m", "-A", "-p", "com.apple.FinderSync"]
            )
        ])
    }

    func testCheckParsesCommandOutput() {
        let runner = StubCommandRunner(result: .success(CommandResult(stdout: "+    ai.shili.AgentDrop.FinderSync(0.2.4)\n", stderr: "")))

        let availability = FinderExtensionAvailabilityChecker.check(runner: runner)

        XCTAssertEqual(availability.status, .enabled)
    }
}
```

- [ ] **Step 4: Run availability tests to verify they fail**

Run: `swift test --filter FinderExtensionAvailabilityTests`

Expected: FAIL because `FinderExtensionAvailability` and `FinderExtensionAvailabilityChecker` do not exist.

- [ ] **Step 5: Implement minimal core availability code**

Create `Sources/AgentDropCore/FinderExtensionAvailability.swift`:

```swift
import Foundation

public enum FinderExtensionAvailabilityStatus: Equatable, Sendable {
    case enabled
    case disabled
    case notRegistered
    case unknown(String)

    public var needsSetup: Bool {
        switch self {
        case .enabled:
            return false
        case .disabled, .notRegistered, .unknown:
            return true
        }
    }
}

public struct FinderExtensionAvailability: Equatable, Sendable {
    public static let bundleIdentifier = "ai.shili.AgentDrop.FinderSync"
    public static let extensionPointIdentifier = "com.apple.FinderSync"

    public let bundleIdentifier: String
    public let status: FinderExtensionAvailabilityStatus

    public init(
        bundleIdentifier: String = FinderExtensionAvailability.bundleIdentifier,
        status: FinderExtensionAvailabilityStatus
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.status = status
    }

    public static func parse(
        pluginkitOutput: String,
        bundleIdentifier: String = FinderExtensionAvailability.bundleIdentifier
    ) -> FinderExtensionAvailability {
        for rawLine in pluginkitOutput.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.contains(bundleIdentifier) else { continue }
            let status: FinderExtensionAvailabilityStatus = rawLine.first == "+" ? .enabled : .disabled
            return FinderExtensionAvailability(bundleIdentifier: bundleIdentifier, status: status)
        }

        return FinderExtensionAvailability(bundleIdentifier: bundleIdentifier, status: .notRegistered)
    }
}

public enum FinderExtensionAvailabilityChecker {
    public static func check(runner: CommandRunning = ProcessCommandRunner()) -> FinderExtensionAvailability {
        do {
            let result = try runner.run(
                CommandInvocation(
                    executable: "/usr/bin/pluginkit",
                    arguments: ["-m", "-A", "-p", FinderExtensionAvailability.extensionPointIdentifier]
                )
            )
            return FinderExtensionAvailability.parse(pluginkitOutput: result.stdout)
        } catch {
            let message: String
            if let commandError = error as? CommandError {
                message = commandError.userMessage
            } else {
                message = String(describing: error)
            }
            return FinderExtensionAvailability(status: .unknown(message))
        }
    }
}
```

- [ ] **Step 6: Add `/Volumes` to monitored directories**

Modify `Sources/AgentDropCore/FinderSyncDirectoryScope.swift` so `monitoredDirectories(home:)` appends `/Volumes` once:

```swift
public enum FinderSyncDirectoryScope {
    public static func monitoredDirectories(home: URL) -> [URL] {
        var homes = [home]
        if home.path.hasPrefix("/Users/") {
            homes.append(URL(fileURLWithPath: "/System/Volumes/Data\(home.path)", isDirectory: true))
        }

        var directories: [URL] = []
        for base in homes {
            directories.append(base)
            directories.append(base.appendingPathComponent("Desktop", isDirectory: true))
            directories.append(base.appendingPathComponent("Documents", isDirectory: true))
            directories.append(base.appendingPathComponent("Downloads", isDirectory: true))
        }
        directories.append(URL(fileURLWithPath: "/Volumes", isDirectory: true))
        return directories
    }
}
```

- [ ] **Step 7: Update existing exact set expectation**

In `Tests/AgentDropCoreTests/FinderSyncDirectoryScopeTests.swift`, add `"/Volumes"` to the expected `Set(paths)` in `testBuildsFinderSyncDirectoriesFromResolvedHome`.

- [ ] **Step 8: Run task tests**

Run: `swift test --filter FinderSyncDirectoryScopeTests && swift test --filter FinderExtensionAvailabilityTests`

Expected: PASS.

### Task 2: Drop Page Setup Notice And Documentation

**Files:**
- Modify: `Sources/AgentDropApp/AgentDropApp.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: `FinderExtensionAvailabilityChecker.check()`
- Consumes: `FinderExtensionAvailabilityStatus.needsSetup`
- Produces: a non-blocking setup notice in `DropLandingView`.

- [ ] **Step 1: Add app state and refresh hooks**

In `DropLandingView`, add state:

```swift
    @State private var finderExtensionAvailability = FinderExtensionAvailability(status: .unknown("Not checked yet."))
```

Update `.onAppear`:

```swift
        .onAppear {
            refreshClipboard(preservingStatus: true)
            refreshFinderExtensionAvailability()
        }
```

Update the `.active` scene phase branch:

```swift
            if phase == .active {
                refreshClipboard(preservingStatus: true)
                refreshFinderExtensionAvailability()
            }
```

- [ ] **Step 2: Add the refresh helper**

Add this method inside `DropLandingView`:

```swift
    private func refreshFinderExtensionAvailability() {
        Task.detached {
            let availability = FinderExtensionAvailabilityChecker.check()
            await MainActor.run {
                finderExtensionAvailability = availability
            }
        }
    }
```

- [ ] **Step 3: Add setup notice to Finder workflow card**

In `finderWorkflowCard`, after the secondary descriptive `Text`, insert:

```swift
            if finderExtensionAvailability.status.needsSetup {
                finderExtensionSetupNotice
            }
```

Then add this view in `DropLandingView`:

```swift
    private var finderExtensionSetupNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(finderExtensionSetupMessage, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    openExtensionsSettings()
                } label: {
                    Label("Open System Settings", systemImage: "gearshape")
                }

                Button {
                    restartFinder()
                    refreshFinderExtensionAvailability()
                } label: {
                    Label("Restart Finder", systemImage: "arrow.clockwise")
                }
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.orange.opacity(0.35))
        }
    }
```

- [ ] **Step 4: Add message and actions**

Add these helpers inside `DropLandingView`:

```swift
    private var finderExtensionSetupMessage: String {
        switch finderExtensionAvailability.status {
        case .enabled:
            return ""
        case .disabled:
            return "Finder extension is installed but disabled. Enable Agent Drop in System Settings, then restart Finder."
        case .notRegistered:
            return "Finder extension is not registered with macOS. Open System Settings after reinstalling Agent Drop, then restart Finder."
        case let .unknown(message):
            return "Could not check Finder extension status. Open System Settings to confirm Agent Drop is enabled. \(message)"
        }
    }

    private func openExtensionsSettings() {
        let urls = [
            URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"),
            URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")
        ].compactMap { $0 }

        for url in urls where NSWorkspace.shared.open(url) {
            return
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    private func restartFinder() {
        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/killall"), arguments: ["Finder"])
    }
```

- [ ] **Step 5: Update README setup guidance**

In `README.md`, update the Finder extension install note near the existing manual setup instructions to mention:

```markdown
Agent Drop also checks Finder extension availability in the `Transfer > Drop`
screen. If the Finder menu is missing, use the in-app `Open System Settings`
and `Restart Finder` actions, then retry from Finder.
```

In `README.md` under Finder Extension Notes, add:

```markdown
- The extension monitors local user folders and `/Volumes`, so Finder menus can
  appear for mounted SMB/network shares and external volumes.
```

- [ ] **Step 6: Run build-focused verification**

Run: `swift test`

Expected: PASS.

Run: `xcodebuild -project AgentDrop.xcodeproj -scheme AgentDrop -configuration Debug build CODE_SIGNING_ALLOWED=NO`

Expected: PASS.

## Self-Review

- Spec coverage: Task 1 covers status parsing and `/Volumes`; Task 2 covers app guidance and README updates.
- Placeholder scan: no TODO/TBD placeholders.
- Type consistency: Task 2 consumes the exact public names produced by Task 1.
