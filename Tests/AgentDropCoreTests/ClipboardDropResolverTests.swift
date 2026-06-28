import XCTest
@testable import AgentDropCore

final class ClipboardDropResolverTests: XCTestCase {
    func testSnapshotDefaultsToEmptyClipboard() {
        XCTAssertEqual(
            ClipboardDropSnapshot(),
            ClipboardDropSnapshot(fileURLs: [], hasImageData: false, text: nil)
        )
    }

    func testInvalidReasonMessageUsesRequiredUnsupportedLocalItemsText() {
        let reason = ClipboardDropInvalidReason.unsupportedLocalItems([
            "missing.png: missing",
            "folder.alias: not a regular file",
        ])

        XCTAssertEqual(
            reason.message,
            "Clipboard contains local items that cannot be dropped: missing.png: missing, folder.alias: not a regular file"
        )
    }

    func testResolvesSingleValidLocalFileURL() throws {
        let root = try makeTemporaryDirectory()
        let file = root.appendingPathComponent("demo.png")
        try Data("demo".utf8).write(to: file)

        let snapshot = ClipboardDropSnapshot(fileURLs: [file], hasImageData: false, text: nil)
        let result = ClipboardDropResolver.resolve(snapshot)

        XCTAssertEqual(result, .ready(ClipboardDropReadyItem(
            kind: .files,
            sources: [
                UploadSourceFile(
                    sourceURL: file,
                    remoteName: "demo.png",
                    localDisplayName: "demo.png",
                    isDirectory: false
                )
            ],
            summary: "demo.png ready"
        )))
    }

    func testResolvesMultipleValidLocalFileURLs() throws {
        let root = try makeTemporaryDirectory()
        let first = root.appendingPathComponent("first.png")
        let second = root.appendingPathComponent("second.txt")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)

        let snapshot = ClipboardDropSnapshot(fileURLs: [first, second], hasImageData: true, text: nil)
        let result = ClipboardDropResolver.resolve(snapshot)

        guard case let .ready(item) = result else {
            XCTFail("Expected ready result")
            return
        }
        XCTAssertEqual(item.kind, .files)
        XCTAssertEqual(item.summary, "2 local items ready")
        XCTAssertEqual(item.sources.map(\.remoteName), ["first.png", "second.txt"])
        XCTAssertEqual(item.sources.map(\.localDisplayName), ["first.png", "second.txt"])
        XCTAssertEqual(item.sources.map(\.isDirectory), [false, false])
    }

    func testResolvesValidDirectoryURL() throws {
        let root = try makeTemporaryDirectory()
        let directory = root.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let snapshot = ClipboardDropSnapshot(fileURLs: [directory], hasImageData: false, text: nil)
        let result = ClipboardDropResolver.resolve(snapshot)

        guard case let .ready(item) = result else {
            XCTFail("Expected ready result")
            return
        }
        XCTAssertEqual(item.sources, [
            UploadSourceFile(
                sourceURL: directory,
                remoteName: "assets",
                localDisplayName: "assets",
                isDirectory: true
            )
        ])
        XCTAssertEqual(item.summary, "assets ready")
    }

    func testInvalidWhenAnyLocalFileURLIsMissing() throws {
        let root = try makeTemporaryDirectory()
        let existing = root.appendingPathComponent("demo.png")
        let missing = root.appendingPathComponent("missing.png")
        try Data("demo".utf8).write(to: existing)

        let snapshot = ClipboardDropSnapshot(fileURLs: [existing, missing], hasImageData: true, text: nil)
        let result = ClipboardDropResolver.resolve(snapshot)

        XCTAssertEqual(result, .invalid(.unsupportedLocalItems(["missing.png: missing"])))
    }

    func testIgnoresPlainTextAndRemoteLookingPathText() {
        XCTAssertEqual(
            ClipboardDropResolver.resolve(ClipboardDropSnapshot(
                fileURLs: [],
                hasImageData: false,
                text: "~/.agent-inbox/2026-06-28/demo.png"
            )),
            .empty
        )
        XCTAssertEqual(
            ClipboardDropResolver.resolve(ClipboardDropSnapshot(
                fileURLs: [],
                hasImageData: false,
                text: "devbox:/tmp/demo.png"
            )),
            .empty
        )
        XCTAssertEqual(
            ClipboardDropResolver.resolve(ClipboardDropSnapshot(
                fileURLs: [],
                hasImageData: false,
                text: "/Users/chris/Desktop/demo.png"
            )),
            .empty
        )
    }

    func testUsesImageFallbackWhenNoFileURLsExist() {
        let date = Date(timeIntervalSince1970: 1_782_641_330)
        let snapshot = ClipboardDropSnapshot(fileURLs: [], hasImageData: true, text: nil)

        let result = ClipboardDropResolver.resolve(
            snapshot,
            date: date,
            timeZone: TimeZone(secondsFromGMT: 8 * 3600)!
        )

        XCTAssertEqual(result, .ready(ClipboardDropReadyItem(
            kind: .image(ClipboardImageDrop(
                remoteName: "Screenshot 2026-06-28 at 18.08.50.png",
                localDisplayName: "Screenshot 2026-06-28 at 18.08.50.png"
            )),
            sources: [],
            summary: "Clipboard item ready"
        )))
    }

    func testScreenshotNameDefaultsToCurrentDate() {
        XCTAssertTrue(
            ClipboardDropResolver.screenshotName(timeZone: TimeZone(secondsFromGMT: 0)!)
                .hasPrefix("Screenshot ")
        )
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
