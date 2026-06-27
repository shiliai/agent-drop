import XCTest
@testable import AgentDropCore

final class CLIRemotePathArgumentNormalizerTests: XCTestCase {
    func testRewritesLocalHomeAbsolutePathToRemoteHomePath() {
        let normalizer = CLIRemotePathArgumentNormalizer(localHomeDirectory: "/Users/chris")

        XCTAssertEqual(normalizer.normalize("/Users/chris"), "~")
        XCTAssertEqual(normalizer.normalize("/Users/chris/runs/output.png"), "~/runs/output.png")
        XCTAssertEqual(normalizer.normalize("/Users/chris/runs/a:b.txt"), "~/runs/a:b.txt")
    }

    func testPreservesOtherAbsolutePaths() {
        let normalizer = CLIRemotePathArgumentNormalizer(localHomeDirectory: "/Users/chris")

        XCTAssertEqual(normalizer.normalize("/tmp/out.zip"), "/tmp/out.zip")
        XCTAssertEqual(normalizer.normalize("/Users/christine/runs/output.png"), "/Users/christine/runs/output.png")
    }

    func testPreservesAlreadyRemoteHomeAndHostHintedPaths() {
        let normalizer = CLIRemotePathArgumentNormalizer(localHomeDirectory: "/Users/chris")

        XCTAssertEqual(normalizer.normalize("~/runs/output.png"), "~/runs/output.png")
        XCTAssertEqual(normalizer.normalize("devbox:~/out"), "devbox:~/out")
        XCTAssertEqual(normalizer.normalize("devbox:/Users/chris/out"), "devbox:/Users/chris/out")
    }

    func testNormalizesEachLineInMultilineArgument() {
        let normalizer = CLIRemotePathArgumentNormalizer(localHomeDirectory: "/Users/chris")

        XCTAssertEqual(
            normalizer.normalize("""
            /Users/chris/runs/output.png
            /tmp/out.zip
            """),
            """
            ~/runs/output.png
            /tmp/out.zip
            """
        )
    }
}
