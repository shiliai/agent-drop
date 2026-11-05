import Foundation
@testable import AgentDropCore

/// Executes the generated remote shell commands and real rsync server protocol in an isolated home.
/// Only the SSH transport is substituted; no user's SSH config or servers are contacted.
final class TransferTestTransport: CancellableProgressReportingCommandRunning {
    let root: URL
    let home: URL
    let downloads: URL
    let target = SSHTarget(name: "isolated", source: .config)
    let clipboard = TransferTestClipboard()
    private let runner: ProcessCommandRunner
    private let ssh: URL
    var invocations: [CommandInvocation] = []
    var rsyncResults: [CommandResult] = []
    var bandwidthLimit: Int?
    var afterRsync: (() throws -> Void)?
    var failChecksums = false
    var sshOverride: ((String) -> CommandResult?)?
    var rsyncFailure: CommandResult?

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("agent-drop-test-" + UUID().uuidString)
        home = root.appendingPathComponent("home")
        downloads = root.appendingPathComponent("downloads")
        ssh = root.appendingPathComponent("ssh")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        try "#!/bin/sh\nshift\nexec /bin/sh -c \"$*\"\n".write(to: ssh, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: ssh.path)
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = home.path
        runner = ProcessCommandRunner(environment: environment)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    var rsyncCount: Int { invocations.filter { $0.executable == "/usr/bin/rsync" }.count }

    func upload(clock: Clock = FixedClock(date: Date(timeIntervalSince1970: 1_781_510_400))) -> UploadService {
        UploadService(runner: self, clipboard: clipboard, clock: clock)
    }

    func download() -> DownloadService { DownloadService(runner: self, clipboard: clipboard) }

    func file(_ relative: String, text: String) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    func uploadedURL(_ file: UploadedFile) -> URL {
        home.appendingPathComponent(String(file.remoteDisplayPath.dropFirst(2)))
    }

    func pull(_ path: String, cancellation: TransferCancellation? = nil, progress: TransferProgressHandler? = nil) throws -> [DownloadedFile] {
        try download().download(remotePaths: [RemotePath(hostHint: nil, path: path)], target: target, destinationRoot: downloads,
                                progress: progress, cancellation: cancellation)
    }

    func run(_ invocation: CommandInvocation) throws -> CommandResult { try run(invocation, progress: nil, cancellation: nil) }

    func run(_ invocation: CommandInvocation, progress: (@Sendable (String) -> Void)?) throws -> CommandResult {
        try run(invocation, progress: progress, cancellation: nil)
    }

    func run(_ invocation: CommandInvocation, progress: (@Sendable (String) -> Void)?, cancellation: TransferCancellation?) throws -> CommandResult {
        invocations.append(invocation)
        if invocation.executable == "/usr/bin/ssh" {
            if let result = sshOverride?(invocation.arguments[1]) { return result }
            if failChecksums && invocation.arguments[1].contains("sha256sum") {
                return .failure(exitCode: 1, stdout: "", stderr: "checksum read failed")
            }
            return try runner.run(CommandInvocation(executable: "/bin/sh", arguments: ["-c", invocation.arguments[1]]), cancellation: cancellation)
        }
        if invocation.executable == "/usr/bin/rsync" {
            if let rsyncFailure { return rsyncFailure }
            var args = ["-e", ssh.path, "--stats"]
            if let bandwidthLimit { args += ["--bwlimit=\(bandwidthLimit)"] }
            args += invocation.arguments
            let result = try runner.run(CommandInvocation(executable: invocation.executable, arguments: args), progress: progress, cancellation: cancellation)
            rsyncResults.append(result)
            try afterRsync?()
            return result
        }
        return try runner.run(invocation, progress: progress, cancellation: cancellation)
    }
}

final class TransferTestClipboard: ClipboardWriting {
    var text: String?
    var fail = false
    func write(_ text: String) throws {
        if fail { throw ClipboardError.writeFailed("pasteboard unavailable") }
        self.text = text
    }
}
