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

    func testHistoryFileURLUsesContainerRelativePathWhenHomeIsAlreadyFinderExtensionContainer() {
        let containerHome = URL(
            fileURLWithPath: "/Users/chris/Library/Containers/ai.shili.AgentDrop.FinderSync/Data",
            isDirectory: true
        )

        let url = UploadHistoryStore.defaultHistoryFileURL(home: containerHome)

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

    func testConcurrentAppendsOnOneStorePreserveAllEntriesNewestFirst() throws {
        let root = try temporaryDirectory()
        let entryCount = 200
        let store = UploadHistoryStore(
            historyFileURL: root.appendingPathComponent("upload-history.json"),
            limit: entryCount
        )
        let start = DispatchSemaphore(value: 0)
        let group = DispatchGroup()
        let errors = ErrorRecorder()

        for index in 0..<entryCount {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                start.wait()
                defer { group.leave() }

                do {
                    try store.append(Self.entry(index: index))
                } catch {
                    errors.append(error)
                }
            }
        }

        for _ in 0..<entryCount {
            start.signal()
        }

        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)
        XCTAssertTrue(errors.isEmpty, "Unexpected append errors: \(errors.values)")

        let loaded = try store.load()
        XCTAssertEqual(loaded.count, entryCount)
        XCTAssertEqual(loaded.map(\.targetName), (0..<entryCount).reversed().map { "target-\($0)" })
    }

    func testCorruptJSONIsPreservedAndHistoryResets() throws {
        let root = try temporaryDirectory()
        let historyURL = root.appendingPathComponent("upload-history.json")
        let corruptData = Data("not-json".utf8)
        try corruptData.write(to: historyURL)
        let store = UploadHistoryStore(historyFileURL: historyURL)

        let loaded = try store.load()

        XCTAssertEqual(loaded, [])
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertTrue(files.contains("upload-history.json"))
        let corruptBackupName = try XCTUnwrap(files.first { $0.hasPrefix("upload-history.json.corrupt-") })
        let corruptBackupURL = root.appendingPathComponent(corruptBackupName)
        XCTAssertEqual(try Data(contentsOf: corruptBackupURL), corruptData)
        let resetData = try Data(contentsOf: historyURL)
        XCTAssertEqual(try JSONDecoder.agentDropHistory.decode([UploadHistoryEntry].self, from: resetData), [])
    }

    func testFilesystemReadErrorsAreNotTreatedAsCorruptJSON() throws {
        let root = try temporaryDirectory()
        let historyURL = root.appendingPathComponent("upload-history.json")
        try FileManager.default.createDirectory(at: historyURL, withIntermediateDirectories: true)
        let store = UploadHistoryStore(historyFileURL: historyURL)

        XCTAssertThrowsError(try store.load())
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: historyURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertFalse(files.contains { $0.hasPrefix("upload-history.json.corrupt-") })
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

    private static func entry(index: Int) -> UploadHistoryEntry {
        UploadHistoryEntry(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!,
            createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
            targetName: "target-\(index)",
            status: .succeeded,
            localFileNames: ["demo-\(index).png"],
            remoteDisplayPaths: ["~/.agent-inbox/2026-06-15/demo-\(index).png"],
            errorMessage: nil
        )
    }
}

private final class ErrorRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Error] = []

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage.isEmpty
    }

    var values: [Error] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ error: Error) {
        lock.lock()
        storage.append(error)
        lock.unlock()
    }
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
