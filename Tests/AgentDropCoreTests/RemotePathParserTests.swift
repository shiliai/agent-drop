import XCTest
@testable import AgentDropCore

final class RemotePathParserTests: XCTestCase {
    func testParsesHomeAbsoluteHostHintedAndMultilinePaths() throws {
        let paths = try RemotePathParser.parse("""
        ~/runs/output.png
        /tmp/build-artifacts
        devbox:~/quoted path/result.txt
        gpu-box:/var/log/app.log
        """)

        XCTAssertEqual(paths, [
            RemotePath(hostHint: nil, path: "~/runs/output.png"),
            RemotePath(hostHint: nil, path: "/tmp/build-artifacts"),
            RemotePath(hostHint: "devbox", path: "~/quoted path/result.txt"),
            RemotePath(hostHint: "gpu-box", path: "/var/log/app.log")
        ])
    }

    func testRejectsBlankOnlyInput() {
        XCTAssertThrowsError(try RemotePathParser.parse(" \n\t ")) { error in
            XCTAssertEqual(error as? RemotePathParserError, .noPaths)
        }
    }

    func testRejectsRelativePathsWithoutHomeOrAbsolutePrefix() {
        XCTAssertThrowsError(try RemotePathParser.parse("runs/output.png")) { error in
            XCTAssertEqual(error as? RemotePathParserError, .unsupportedRelativePath("runs/output.png"))
        }
    }

    func testRejectsHostRelativePaths() {
        XCTAssertThrowsError(try RemotePathParser.parse("devbox:runs/output.png")) { error in
            XCTAssertEqual(error as? RemotePathParserError, .unsupportedRelativePath("devbox:runs/output.png"))
        }
    }

    func testKeepsColonsInsideAbsoluteAndHomePathFilenames() throws {
        let paths = try RemotePathParser.parse("""
        /tmp/report:final.txt
        ~/runs/a:b.txt
        """)

        XCTAssertEqual(paths, [
            RemotePath(hostHint: nil, path: "/tmp/report:final.txt"),
            RemotePath(hostHint: nil, path: "~/runs/a:b.txt")
        ])
    }
}
