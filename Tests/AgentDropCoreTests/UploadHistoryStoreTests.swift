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
