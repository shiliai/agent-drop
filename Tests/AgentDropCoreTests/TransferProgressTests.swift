import XCTest
@testable import AgentDropCore

final class TransferProgressTests: XCTestCase {
    func testParsesRsyncProgressLine() {
        let progress = RsyncProgressParser.parse("  1,234,567  42%   12.34MB/s    0:01:23")

        XCTAssertEqual(progress?.completedBytes, 1_234_567)
        XCTAssertEqual(progress?.fractionCompleted, 0.42)
        XCTAssertEqual(progress?.bytesPerSecond, 12_340_000)
        XCTAssertEqual(progress?.estimatedTimeRemaining, 83)
        XCTAssertEqual(progress?.displayText(prefix: "Uploading"), "Uploading - 42% | 12.3 MB/s | ETA 1m 23s")
    }

    func testIgnoresNonProgressOutput() {
        XCTAssertNil(RsyncProgressParser.parse("sending incremental file list"))
        XCTAssertNil(RsyncProgressParser.parse(""))
    }

    func testParsesProgressLineWithCarriageReturn() {
        let progress = RsyncProgressParser.parse("2048  10%  1.00MB/s  0:00:09\r")

        XCTAssertEqual(progress?.fractionCompleted, 0.1)
        XCTAssertEqual(progress?.estimatedTimeRemaining, 9)
    }

    func testParsesBinaryRateUnits() {
        let progress = RsyncProgressParser.parse("1024  1%  2.00MiB/s  0:00:04")

        XCTAssertEqual(progress?.bytesPerSecond, 2 * 1024 * 1024)
        XCTAssertEqual(progress?.etaText, "4s")
    }
}
