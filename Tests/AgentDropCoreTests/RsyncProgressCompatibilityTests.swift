import XCTest
@testable import AgentDropCore

final class RsyncProgressCompatibilityTests: XCTestCase {
    func testUploadUsesCompatibleProgressOptionAndReportsProgress() throws {
        let runner = ProgressCommandRunner(results: [
            .success(stdout: "", stderr: ""),
            .success(stdout: "", stderr: ""),
            .success(stdout: "", stderr: "")
        ])
        let progress = ProgressCapture()
        let service = UploadService(runner: runner)

        let uploaded = try service.upload(
            files: [URL(fileURLWithPath: "/tmp/demo.png")],
            target: SSHTarget(name: "devbox", source: .config),
            copyToClipboard: false,
            progress: { progress.append($0) }
        )

        XCTAssertEqual(uploaded.count, 1)
        XCTAssertEqual(runner.invocations.last?.arguments.first, "--progress")
        XCTAssertEqual(progress.values.first?.fractionCompleted, 0.5)
    }

    func testDownloadUsesCompatibleProgressOptionForFilesAndLargeDirectories() throws {
        for (inspection, expectedStrategy) in [("file\n", DownloadTransferStrategy.rsyncFile), ("directory\n1001\n", .rsyncDirectory)] {
            let root = try makeRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let runner = ProgressCommandRunner(results: [
                .success(stdout: inspection, stderr: ""),
                .success(stdout: "", stderr: "")
            ])
            let progress = ProgressCapture()
            let service = DownloadService(runner: runner)

            let downloaded = try service.download(
                remotePaths: [RemotePath(hostHint: nil, path: "/home/data/archive.tar.gz")],
                target: SSHTarget(name: "relay-310p2", source: .config),
                destinationRoot: root,
                copyToClipboard: false,
                progress: { progress.append($0) }
            )

            XCTAssertEqual(downloaded.first?.strategy, expectedStrategy)
            XCTAssertEqual(runner.invocations.last?.arguments.first, "--progress")
            XCTAssertEqual(progress.values.first?.completedBytes, 1024)
        }
    }

    func testSystemRsyncTransfersFileWithProgressEnabled() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.dat")
        let destination = root.appendingPathComponent("destination.dat")
        let payload = Data(repeating: 42, count: 128 * 1024)
        try payload.write(to: source)
        let progress = ProgressCapture()

        let result = try ProcessCommandRunner().run(CommandInvocation(
            executable: "/usr/bin/rsync",
            arguments: ["--progress", "-a", source.path, destination.path]
        )) { line in
            if let parsed = RsyncProgressParser.parse(line) {
                progress.append(parsed)
            }
        }

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(try Data(contentsOf: destination), payload)
        XCTAssertFalse(progress.values.isEmpty, result.stdout + result.stderr)
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

private final class ProgressCommandRunner: ProgressReportingCommandRunning {
    var invocations: [CommandInvocation] = []
    private var results: [CommandResult]

    init(results: [CommandResult]) {
        self.results = results
    }

    func run(_ invocation: CommandInvocation) throws -> CommandResult {
        invocations.append(invocation)
        return results.removeFirst()
    }

    func run(_ invocation: CommandInvocation, progress: (@Sendable (String) -> Void)?) throws -> CommandResult {
        progress?("1024  50%  1.00MB/s  0:00:01")
        return try run(invocation)
    }
}

private final class ProgressCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [TransferProgress] = []

    var values: [TransferProgress] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: TransferProgress) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(value)
    }
}
