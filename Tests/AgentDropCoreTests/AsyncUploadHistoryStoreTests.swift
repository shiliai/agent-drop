import XCTest
@testable import AgentDropCore

final class AsyncUploadHistoryStoreTests: XCTestCase {
    func testAppendAndLoadUseWrappedHistoryStore() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let historyURL = root.appendingPathComponent("upload-history.json")
        let store = UploadHistoryStore(historyFileURL: historyURL)
        let asyncStore = AsyncUploadHistoryStore(store: store)
        let entry = UploadHistoryEntry(
            id: UUID(uuidString: "45454545-4545-4545-4545-454545454545")!,
            createdAt: Date(timeIntervalSince1970: 1_782_000_000),
            direction: .download,
            targetName: "devbox",
            status: .succeeded,
            localFileNames: ["output.png"],
            remoteDisplayPaths: ["~/runs/output.png"],
            localDisplayPaths: ["/Users/chris/Downloads/Agent Drop/output.png"],
            errorMessage: nil
        )

        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try await asyncStore.append(entry)

        let loaded = try await asyncStore.load()
        XCTAssertEqual(loaded, [entry])
    }
}
