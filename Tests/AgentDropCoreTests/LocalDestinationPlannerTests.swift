import XCTest
@testable import AgentDropCore

final class LocalDestinationPlannerTests: XCTestCase {
    func testReservesNonOverwritingFileAndCleansItUp() throws {
        let root = try makeLocalDestinationTemporaryDirectory().appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: root.appendingPathComponent("output.png").path, contents: Data())

        let reserved = try LocalDestinationPlanner().reserve(root: root, remotePath: "~/runs/output.png", kind: .file)

        XCTAssertEqual(reserved, ReservedLocalDestination(url: root.appendingPathComponent("output-2.png"), kind: .file))
        XCTAssertTrue(FileManager.default.fileExists(atPath: reserved.url.path))

        try reserved.cleanup()

        XCTAssertFalse(FileManager.default.fileExists(atPath: reserved.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("output.png").path))
    }

    func testCreatesRootAndReservesNonOverwritingDirectory() throws {
        let root = try makeLocalDestinationTemporaryDirectory().appendingPathComponent("Agent Drop", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("build-artifacts", isDirectory: true), withIntermediateDirectories: true)

        let reserved = try LocalDestinationPlanner().reserve(root: root, remotePath: "/tmp/build-artifacts", kind: .directory)

        XCTAssertEqual(reserved, ReservedLocalDestination(url: root.appendingPathComponent("build-artifacts-2", isDirectory: true), kind: .directory))
        XCTAssertTrue(isDirectory(reserved.url))

        try reserved.cleanup()

        XCTAssertFalse(FileManager.default.fileExists(atPath: reserved.url.path))
        XCTAssertTrue(isDirectory(root.appendingPathComponent("build-artifacts", isDirectory: true)))
    }

    func testRejectsInvalidRemoteBasename() throws {
        let root = try makeLocalDestinationTemporaryDirectory()

        XCTAssertThrowsError(try LocalDestinationPlanner().reserve(root: root, remotePath: "~/", kind: .file)) { error in
            XCTAssertEqual(error as? LocalDestinationPlannerError, .invalidRemotePath("~/"))
        }
    }

    func testRejectsParentDirectoryBasename() throws {
        let root = try makeLocalDestinationTemporaryDirectory()

        for remotePath in ["/tmp/..", "~/runs/.."] {
            XCTAssertThrowsError(try LocalDestinationPlanner().reserve(root: root, remotePath: remotePath, kind: .file)) { error in
                XCTAssertEqual(error as? LocalDestinationPlannerError, .invalidRemotePath(remotePath))
            }
        }
    }

    func testTreatsFileAndDirectoryConflictsTheSameWhenChoosingNextName() throws {
        let root = try makeLocalDestinationTemporaryDirectory()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("output.png", isDirectory: true), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: root.appendingPathComponent("assets").path, contents: Data())

        let fileReservation = try LocalDestinationPlanner().reserve(root: root, remotePath: "/tmp/output.png", kind: .file)
        let directoryReservation = try LocalDestinationPlanner().reserve(root: root, remotePath: "/tmp/assets", kind: .directory)

        XCTAssertEqual(fileReservation.url.lastPathComponent, "output-2.png")
        XCTAssertEqual(directoryReservation.url.lastPathComponent, "assets-2")
    }

    func testFailsAfterExhaustingCandidateRange() throws {
        let root = try makeLocalDestinationTemporaryDirectory()
        for name in LocalNamePlanner(originalName: "output.png").candidates(prefixCount: 100) {
            FileManager.default.createFile(atPath: root.appendingPathComponent(name).path, contents: Data())
        }

        XCTAssertThrowsError(try LocalDestinationPlanner().reserve(root: root, remotePath: "/tmp/output.png", kind: .file)) { error in
            XCTAssertEqual(error as? LocalDestinationPlannerError, .noAvailableLocalName("output.png"))
        }
    }

    func testCleanupRemovesPartialDirectoryContents() throws {
        let root = try makeLocalDestinationTemporaryDirectory()
        let reserved = try LocalDestinationPlanner().reserve(root: root, remotePath: "/tmp/build-artifacts", kind: .directory)
        let partial = reserved.url.appendingPathComponent("nested/output.txt")
        try FileManager.default.createDirectory(at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: partial.path, contents: Data())

        try reserved.cleanup()

        XCTAssertFalse(FileManager.default.fileExists(atPath: reserved.url.path))
    }
}

private func makeLocalDestinationTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func isDirectory(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
    return exists && isDirectory.boolValue
}
