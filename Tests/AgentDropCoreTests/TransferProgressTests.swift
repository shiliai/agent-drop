import XCTest
@testable import AgentDropCore

private final class DirectoryProgressCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [TransferProgress] = []

    var values: [TransferProgress] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ progress: TransferProgress) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(progress)
    }
}

final class TransferProgressTests: XCTestCase {
    func testLegacyProgressDecodesWithoutDirectoryMetadata() throws {
        let json = #"{"completedBytes":42,"fractionCompleted":0.5}"#
        let progress = try JSONDecoder().decode(TransferProgress.self, from: Data(json.utf8))
        XCTAssertNil(progress.totalFiles)
        XCTAssertNil(progress.completedFiles)
        XCTAssertNil(progress.currentFile)
    }

    func testDirectoryProgressTracksFileNamesAndCompletedCounts() {
        let capture = DirectoryProgressCapture()
        let tracker = DirectoryDownloadProgress(totalFiles: 4, initialCompleted: 2) { capture.append($0) }
        tracker.start()
        tracker.consume("AD:>f++++++++:folder/a name.txt")
        tracker.consume("100 50% 1.00MB/s 0:00:01")
        tracker.consume("200 100% 1.00MB/s 0:00:00 (xfer#1, to-check=0/2)")
        tracker.consume("200 100% 1.00MB/s 0:00:00 (xfer#1, to-check=0/2)")
        XCTAssertEqual(capture.values.first?.fileCountText, "2 / 4 files")
        XCTAssertEqual(capture.values.last?.fileCountText, "3 / 4 files")
        XCTAssertEqual(capture.values.last?.currentFile, "folder/a name.txt")
    }
    func testEmptyFileRsyncProgressOmitsNonFinitePercentage() throws {
        // macOS /usr/bin/rsync emits this line when transferring an empty file.
        let progress = try XCTUnwrap(RsyncProgressParser.parse("0 nan% 00:00:00 (xfer#1, to-check=0/1)"))
        XCTAssertNil(progress.fractionCompleted)
        XCTAssertEqual(progress.displayText(prefix: "Uploading"), "Uploading - ETA 0s")
    }

    func testNonFinitePercentagesAreOmitted() {
        for fraction in [Double.nan, .infinity, -.infinity] {
            let progress = makeProgress(fraction: fraction)
            XCTAssertNil(progress.percentText)
        }
    }

    func testFinitePercentagesAreClampedBeforeConversion() {
        for (fraction, expected) in [(-Double.greatestFiniteMagnitude, "0%"), (-0.1, "0%"), (0, "0%"), (0.425, "43%"), (1, "100%"), (1.1, "100%"), (Double.greatestFiniteMagnitude, "100%")] {
            XCTAssertEqual(makeProgress(fraction: fraction).percentText, expected)
        }
    }

    func testInvalidOrUnrepresentableMetricsAreOmitted() {
        for value in [Double.nan, .infinity, -.infinity, .greatestFiniteMagnitude, Double(Int.max)] {
            let progress = TransferProgress(completedBytes: 0, fractionCompleted: nil, bytesPerSecond: value.isFinite ? nil : value, estimatedTimeRemaining: value)
            XCTAssertNil(progress.etaText)
            XCTAssertNil(progress.speedText)
        }
        XCTAssertEqual(TransferProgress(completedBytes: 0, fractionCompleted: nil, bytesPerSecond: nil, estimatedTimeRemaining: -1).etaText, "0s")
    }

    func testParserRejectsNonFinitePercentageTokens() {
        for token in ["nan", "inf", "-inf", "1e309"] {
            let progress = RsyncProgressParser.parse("0 \(token)% 00:00:00")
            XCTAssertNil(progress?.fractionCompleted)
            XCTAssertEqual(progress?.etaText, "0s")
        }
    }

    private func makeProgress(fraction: Double) -> TransferProgress {
        TransferProgress(completedBytes: 0, fractionCompleted: fraction, bytesPerSecond: nil, estimatedTimeRemaining: nil)
    }

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
