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
