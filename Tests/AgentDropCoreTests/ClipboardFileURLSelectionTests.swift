import XCTest
@testable import AgentDropCore

final class ClipboardFileURLSelectionTests: XCTestCase {
    func testUsesTypedFileURLsWhenAvailable() {
        let typed = [
            URL(fileURLWithPath: "/tmp/demo.png")
        ]

        let urls = ClipboardFileURLSelection.fileURLs(
            typedURLs: typed,
            legacyFilePaths: ["/tmp/legacy.png"]
        )

        XCTAssertEqual(urls, typed)
    }

    func testFallsBackToLegacyFilenamesWhenTypedURLsAreEmpty() {
        let urls = ClipboardFileURLSelection.fileURLs(
            typedURLs: [],
            legacyFilePaths: ["/tmp/legacy.png"]
        )

        XCTAssertEqual(urls, [URL(fileURLWithPath: "/tmp/legacy.png")])
    }

    func testFiltersNonFileTypedURLsBeforeChoosingFallback() {
        let urls = ClipboardFileURLSelection.fileURLs(
            typedURLs: [URL(string: "https://example.com/demo.png")!],
            legacyFilePaths: ["/tmp/legacy.png"]
        )

        XCTAssertEqual(urls, [URL(fileURLWithPath: "/tmp/legacy.png")])
    }
}
