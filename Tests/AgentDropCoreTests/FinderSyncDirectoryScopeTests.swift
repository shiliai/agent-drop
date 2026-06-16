import XCTest
@testable import AgentDropCore

final class FinderSyncDirectoryScopeTests: XCTestCase {
    func testResolvesAccountHomeOutsideSandboxFallback() {
        let sandboxHome = URL(
            fileURLWithPath: "/Users/chris/Library/Containers/ai.shili.AgentDrop.FinderSync/Data",
            isDirectory: true
        )

        let home = HostHomeDirectoryResolver.resolve(accountHomePath: "/Users/chris", fallback: sandboxHome)

        XCTAssertEqual(home.path, "/Users/chris")
    }

    func testFallsBackWhenAccountHomeIsUnavailable() {
        let fallback = URL(fileURLWithPath: "/tmp/agent-drop-home", isDirectory: true)

        let home = HostHomeDirectoryResolver.resolve(accountHomePath: nil, fallback: fallback)

        XCTAssertEqual(home.path, "/tmp/agent-drop-home")
    }

    func testBuildsFinderSyncDirectoriesFromResolvedHome() {
        let home = URL(fileURLWithPath: "/Users/chris", isDirectory: true)

        let paths = FinderSyncDirectoryScope.monitoredDirectories(home: home).map(\.path)

        XCTAssertEqual(
            Set(paths),
            [
                "/Users/chris",
                "/Users/chris/Desktop",
                "/Users/chris/Documents",
                "/Users/chris/Downloads",
                "/System/Volumes/Data/Users/chris",
                "/System/Volumes/Data/Users/chris/Desktop",
                "/System/Volumes/Data/Users/chris/Documents",
                "/System/Volumes/Data/Users/chris/Downloads"
            ]
        )
    }

    func testIncludesDataVolumeMirrorForUserHome() {
        let home = URL(fileURLWithPath: "/Users/chris", isDirectory: true)

        let paths = FinderSyncDirectoryScope.monitoredDirectories(home: home).map(\.path)

        XCTAssertTrue(paths.contains("/System/Volumes/Data/Users/chris"))
        XCTAssertTrue(paths.contains("/System/Volumes/Data/Users/chris/Desktop"))
        XCTAssertTrue(paths.contains("/System/Volumes/Data/Users/chris/Documents"))
        XCTAssertTrue(paths.contains("/System/Volumes/Data/Users/chris/Downloads"))
    }
}
