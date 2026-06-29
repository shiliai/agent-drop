import XCTest
@testable import AgentDropCore

final class ClipboardPathCopierTests: XCTestCase {
    func testCopiesUploadedRemotePaths() {
        let clipboard = FakePathClipboard()
        let uploaded = [
            UploadedFile(localURL: URL(fileURLWithPath: "/tmp/one.png"), remoteDisplayPath: "~/.agent-inbox/one.png"),
            UploadedFile(localURL: URL(fileURLWithPath: "/tmp/two.png"), remoteDisplayPath: "~/.agent-inbox/two.png")
        ]

        let result = ClipboardPathCopier.copyRemotePaths(from: uploaded, clipboard: clipboard)

        XCTAssertEqual(result, .copied)
        XCTAssertEqual(clipboard.text, "~/.agent-inbox/one.png\n~/.agent-inbox/two.png")
    }

    func testReportsClipboardFailureWithoutThrowing() {
        let clipboard = FakePathClipboard(error: ClipboardError.writeFailed("pasteboard unavailable"))
        let uploaded = [
            UploadedFile(localURL: URL(fileURLWithPath: "/tmp/demo.png"), remoteDisplayPath: "~/.agent-inbox/demo.png")
        ]

        let result = ClipboardPathCopier.copyRemotePaths(from: uploaded, clipboard: clipboard)

        XCTAssertEqual(result, .failed("pasteboard unavailable"))
        XCTAssertNil(clipboard.text)
    }
}

private final class FakePathClipboard: ClipboardWriting {
    var text: String?
    let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func write(_ text: String) throws {
        if let error {
            throw error
        }
        self.text = text
    }
}
