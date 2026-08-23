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

        let paths = FinderSyncDirectoryScope.monitoredDirectories(home: home, mountedVolumes: []).map(\.path)

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

        let paths = FinderSyncDirectoryScope.monitoredDirectories(home: home, mountedVolumes: []).map(\.path)

        XCTAssertTrue(paths.contains("/System/Volumes/Data/Users/chris"))
        XCTAssertTrue(paths.contains("/System/Volumes/Data/Users/chris/Desktop"))
        XCTAssertTrue(paths.contains("/System/Volumes/Data/Users/chris/Documents"))
        XCTAssertTrue(paths.contains("/System/Volumes/Data/Users/chris/Downloads"))
    }

    func testIncludesMountedNetworkAndExternalVolumes() {
        let home = URL(fileURLWithPath: "/Users/chris", isDirectory: true)

        let paths = FinderSyncDirectoryScope.monitoredDirectories(
            home: home,
            mountedVolumes: [
                URL(fileURLWithPath: "/Volumes/home", isDirectory: true),
                URL(fileURLWithPath: "/Volumes/External Drive", isDirectory: true)
            ]
        ).map(\.path)

        XCTAssertTrue(paths.contains("/Volumes/home"))
        XCTAssertTrue(paths.contains("/Volumes/External Drive"))
    }

    func testDeduplicatesMountedVolumes() {
        let home = URL(fileURLWithPath: "/Users/chris", isDirectory: true)

        let paths = FinderSyncDirectoryScope.monitoredDirectories(
            home: home,
            mountedVolumes: [
                URL(fileURLWithPath: "/Volumes/home", isDirectory: true),
                URL(fileURLWithPath: "/Volumes/home/", isDirectory: true)
            ]
        ).map(\.path)

        XCTAssertEqual(paths.filter { $0 == "/Volumes/home" }.count, 1)
    }
}
