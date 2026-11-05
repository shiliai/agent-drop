import XCTest
@testable import AgentDropCore

final class ResumableTransferTests: XCTestCase {
    func testUploadSkipsActualSHAIdenticalFileAcrossDaysAndServiceInstances() throws {
        let transport = try TransferTestTransport()
        let source = try transport.file("source/client's 文件\noutput.txt", text: "same bytes")
        let first = try transport.upload().upload(files: [source], target: transport.target)
        let count = transport.rsyncCount
        let nextDay = FixedClock(date: Date(timeIntervalSince1970: 1_781_596_800))
        let second = try transport.upload(clock: nextDay).upload(files: [source], target: transport.target)
        XCTAssertEqual(second.first?.remoteDisplayPath, first.first?.remoteDisplayPath)
        XCTAssertEqual(second.first?.wasSkipped, true)
        XCTAssertEqual(transport.rsyncCount, count)
        XCTAssertEqual(transport.clipboard.text, first.first?.remoteDisplayPath)
    }

    func testDownloadSkipsExistingFileWithoutAnyHistory() throws {
        let transport = try TransferTestTransport()
        _ = try transport.file("home/runs/output.txt", text: "already here")
        _ = try transport.file("downloads/output.txt", text: "already here")
        let result = try transport.pull("~/runs/output.txt")
        XCTAssertEqual(result.first?.wasSkipped, true)
        XCTAssertEqual(transport.rsyncCount, 0)
        XCTAssertEqual(transport.clipboard.text, transport.downloads.appendingPathComponent("output.txt").path)
    }

    func testUploadDoesNotSkipSameSizeSameTimestampDifferentBytesAndKeepsOriginal() throws {
        let transport = try TransferTestTransport()
        let source = try transport.file("source/output.txt", text: "abc")
        let first = try XCTUnwrap(transport.upload().upload(files: [source], target: transport.target).first)
        let remote = transport.uploadedURL(first)
        let date = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: remote.path)[.modificationDate] as? Date)
        try Data("xyz".utf8).write(to: remote)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: remote.path)
        let second = try XCTUnwrap(transport.upload().upload(files: [source], target: transport.target).first)
        XCTAssertFalse(second.wasSkipped)
        XCTAssertTrue(second.remoteDisplayPath.hasSuffix("output-2.txt"))
        XCTAssertEqual(try String(contentsOf: remote, encoding: .utf8), "xyz")
        XCTAssertEqual(try String(contentsOf: transport.uploadedURL(second), encoding: .utf8), "abc")
        let third = try transport.upload().upload(files: [source], target: transport.target)
        XCTAssertEqual(third.first?.remoteDisplayPath, second.remoteDisplayPath)
        XCTAssertEqual(third.first?.wasSkipped, true)
    }

    func testDownloadDoesNotSkipModifiedOutputAndFindsSHAIdenticalCollisionName() throws {
        let transport = try TransferTestTransport()
        _ = try transport.file("home/runs/output.txt", text: "abc")
        let first = try XCTUnwrap(transport.pull("~/runs/output.txt").first)
        let date = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: first.localURL.path)[.modificationDate] as? Date)
        try Data("xyz".utf8).write(to: first.localURL)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: first.localURL.path)
        let second = try XCTUnwrap(transport.pull("~/runs/output.txt").first)
        XCTAssertFalse(second.wasSkipped)
        XCTAssertEqual(second.localURL.lastPathComponent, "output-2.txt")
        XCTAssertEqual(try String(contentsOf: first.localURL, encoding: .utf8), "xyz")
        XCTAssertEqual(try String(contentsOf: second.localURL, encoding: .utf8), "abc")
        let count = transport.rsyncCount
        XCTAssertEqual(try transport.pull("~/runs/output.txt").first?.localURL, second.localURL)
        XCTAssertEqual(transport.rsyncCount, count)
    }

    func testDeletedOutputsAreTransferredAgainInBothDirections() throws {
        let transport = try TransferTestTransport()
        let source = try transport.file("source/output.txt", text: "abc")
        let upload = try XCTUnwrap(transport.upload().upload(files: [source], target: transport.target).first)
        try FileManager.default.removeItem(at: transport.uploadedURL(upload))
        XCTAssertEqual(try transport.upload().upload(files: [source], target: transport.target).first?.wasSkipped, false)
        _ = try transport.file("home/runs/output.txt", text: "download")
        let download = try XCTUnwrap(transport.pull("~/runs/output.txt").first)
        try FileManager.default.removeItem(at: download.localURL)
        XCTAssertEqual(try transport.pull("~/runs/output.txt").first?.wasSkipped, false)
        XCTAssertEqual(transport.rsyncCount, 4)
    }

    func testDirectoriesComparePathsEmptyDirectoriesAndSymlinksInBothDirections() throws {
        let transport = try TransferTestTransport()
        let source = transport.root.appendingPathComponent("source/assets")
        _ = try transport.file("source/assets/sub/a.txt", text: "nested")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("empty"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: source.appendingPathComponent("link").path, withDestinationPath: "sub/a.txt")
        let first = try XCTUnwrap(transport.upload().upload(files: [source], target: transport.target).first)
        XCTAssertEqual(try transport.upload().upload(files: [source], target: transport.target).first?.wasSkipped, true)
        let download = try XCTUnwrap(transport.pull(first.remoteDisplayPath).first)
        XCTAssertEqual(try transport.pull(first.remoteDisplayPath).first?.wasSkipped, true)
        try FileManager.default.removeItem(at: download.localURL.appendingPathComponent("empty"))
        let replaced = try XCTUnwrap(transport.pull(first.remoteDisplayPath).first)
        XCTAssertFalse(replaced.wasSkipped)
        XCTAssertEqual(replaced.localURL.lastPathComponent, "assets-2")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: replaced.localURL.appendingPathComponent("link").path), "sub/a.txt")
    }

    func testCancelledUploadRetainsPartialBytesAndRetryUsesRsyncDelta() throws {
        try exerciseResume(upload: true)
    }

    func testCancelledDownloadRetainsPartialBytesAndRetryUsesRsyncDelta() throws {
        try exerciseResume(upload: false)
    }

    func testCancelledDirectoryUploadResumesCompletedAndPartialFiles() throws {
        try exerciseResume(upload: true, directory: true)
    }

    func testCancelledDirectoryDownloadResumesCompletedAndPartialFiles() throws {
        try exerciseResume(upload: false, directory: true)
    }

    private func exerciseResume(upload: Bool, directory: Bool = false) throws {
        let transport = try TransferTestTransport()
        let relative = upload ? "source/" : "home/runs/"
        let sourceFile = try transport.file(relative + (directory ? "assets/large.dat" : "large.dat"), text: "")
        let source = directory ? sourceFile.deletingLastPathComponent() : sourceFile
        let remote = directory ? "~/runs/assets" : "~/runs/large.dat"
        if directory { _ = try transport.file(relative + "assets/000-small.txt", text: "completed first") }
        // Nontrivial data makes a checksum-only or whole-file retry observable in rsync's stats.
        let data = Data((0..<(4 * 1024 * 1024)).map { UInt8(truncatingIfNeeded: ($0 * 17) ^ ($0 >> 8)) })
        try data.write(to: sourceFile)
        let cancellation = TransferCancellation()
        transport.bandwidthLimit = 512
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { cancellation.cancel() }
        if upload {
            XCTAssertThrowsError(try transport.upload().upload(files: [source], target: transport.target, cancellation: cancellation))
        } else {
            XCTAssertThrowsError(try transport.pull(remote, cancellation: cancellation))
        }
        let partialRoot = upload ? transport.home.appendingPathComponent(".agent-inbox/.partial") : transport.downloads.appendingPathComponent(".agent-drop-partial")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: partialRoot, includingPropertiesForKeys: nil))
        let payload = try XCTUnwrap(enumerator.allObjects.compactMap { $0 as? URL }.first { $0.lastPathComponent == "payload" })
        let partialFile = directory ? payload.appendingPathComponent("large.dat") : payload
        let partialSize = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: partialFile.path)[.size] as? NSNumber).intValue
        XCTAssertGreaterThan(partialSize, 0)
        XCTAssertLessThan(partialSize, data.count)
        transport.bandwidthLimit = nil
        let output: URL
        if upload {
            let result = try XCTUnwrap(transport.upload().upload(files: [source], target: transport.target).first)
            XCTAssertFalse(result.wasSkipped)
            output = transport.uploadedURL(result)
        } else {
            let result = try XCTUnwrap(transport.pull(remote).first)
            XCTAssertFalse(result.wasSkipped)
            output = result.localURL
        }
        XCTAssertEqual(try Data(contentsOf: directory ? output.appendingPathComponent("large.dat") : output), data)
        if directory {
            XCTAssertEqual(try String(contentsOf: output.appendingPathComponent("000-small.txt"), encoding: .utf8), "completed first")
        }
        let stats = try XCTUnwrap(transport.rsyncResults.last).stdout
        let matched = stats.split(separator: "\n").first { $0.lowercased().contains("matched data:") }
        XCTAssertNotNil(matched, stats)
        let matchedBytes = matched?.split(separator: ":").last?.split(separator: " ").first.map { String($0).replacingOccurrences(of: ",", with: "") }
        XCTAssertGreaterThan(Int(matchedBytes ?? "") ?? 0, 0, stats)
    }

    func testChecksumFailureNeverSkipsOrPublishesOutput() throws {
        let transport = try TransferTestTransport()
        let source = try transport.file("source/output.txt", text: "abc")
        transport.failChecksums = true
        XCTAssertThrowsError(try transport.upload().upload(files: [source], target: transport.target))
        XCTAssertFalse(FileManager.default.fileExists(atPath: transport.home.appendingPathComponent(".agent-inbox/2026-06-15/output.txt").path))
        _ = try transport.file("home/runs/output.txt", text: "download")
        XCTAssertThrowsError(try transport.pull("~/runs/output.txt"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: transport.downloads.appendingPathComponent("output.txt").path))
        XCTAssertNil(transport.clipboard.text)
    }

    func testSourceChangesDuringDownloadFailClosed() throws {
        let transport = try TransferTestTransport()
        let source = try transport.file("home/runs/output.txt", text: "before")
        transport.afterRsync = { try Data("after!".utf8).write(to: source) }
        XCTAssertThrowsError(try transport.pull("~/runs/output.txt"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: transport.downloads.appendingPathComponent("output.txt").path))
    }

    func testSourceChangesDuringUploadFailClosed() throws {
        let transport = try TransferTestTransport()
        let source = try transport.file("source/output.txt", text: "before")
        transport.afterRsync = { try Data("after!".utf8).write(to: source) }
        XCTAssertThrowsError(try transport.upload().upload(files: [source], target: transport.target))
        XCTAssertFalse(FileManager.default.fileExists(atPath: transport.home.appendingPathComponent(".agent-inbox/2026-06-15/output.txt").path))
    }

    func testSHA256UsesKnownDigestAndMatchesRemoteManifest() throws {
        let transport = try TransferTestTransport()
        let source = try transport.file("home/test.txt", text: "abc")
        let expected = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        XCTAssertEqual(try TransferIntegrity.localFingerprint(source, cancellation: nil), expected)
        XCTAssertEqual(try TransferIntegrity.remoteFingerprint("~/test.txt", target: transport.target, runner: transport, cancellation: nil), expected)
    }

    func testSkipCountSurvivesHistoryPersistenceAndMetricUpdates() throws {
        let file = UploadedFile(localURL: URL(fileURLWithPath: "/tmp/a"), remoteDisplayPath: "~/a", wasSkipped: true)
        let entry = UploadHistoryEntry.succeeded(targetName: "test", uploadedFiles: [file])
            .withRetryRequest(.upload(target: SSHTarget(name: "test", source: .config), sources: []))
            .withMetrics(startedAt: Date(), completedAt: Date(), totalBytes: 3)
            .updatingProgress(nil)
        let decoded = try JSONDecoder.agentDropHistory.decode(UploadHistoryEntry.self, from: JSONEncoder.agentDropHistory.encode(entry))
        XCTAssertEqual(decoded.skippedCount, 1)
        XCTAssertEqual(decoded.copyPayload, "~/a")
        let downloaded = DownloadedFile(remotePath: "~/a", localURL: URL(fileURLWithPath: "/tmp/a"), localDisplayPath: "/tmp/a", strategy: .rsyncFile, wasSkipped: true)
        XCTAssertEqual(UploadHistoryEntry.downloadSucceeded(targetName: "test", downloadedFiles: [downloaded]).skippedCount, 1)
    }
}
