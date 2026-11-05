import Darwin
import Foundation

public struct DownloadedFile: Equatable, Sendable {
    public let remotePath: String
    public let localURL: URL
    public let localDisplayPath: String
    public let strategy: DownloadTransferStrategy
    public let wasSkipped: Bool

    public init(remotePath: String, localURL: URL, localDisplayPath: String, strategy: DownloadTransferStrategy, wasSkipped: Bool = false) {
        self.remotePath = remotePath
        self.localURL = localURL
        self.localDisplayPath = localDisplayPath
        self.strategy = strategy
        self.wasSkipped = wasSkipped
    }
}

public enum DownloadError: Error, Equatable, Sendable {
    case noRemotePaths
    case hostHintMismatch(hostHint: String, selectedTarget: String)
    case remoteInspectionFailed(String)
    case unsupportedRemotePath(String)
    case destinationReservationFailed(String)
    case rsyncFailed(String)
    case tarFailed(String)
    case clipboardFailed(String)
}

public final class DownloadService {
    private let runner: CommandRunning
    private let pipelineRunner: CommandPiping
    private let clipboard: ClipboardWriting
    private let destinationPlanner: LocalDestinationPlanner
    private let fileManager: FileManager

    public init(
        runner: CommandRunning = ProcessCommandRunner(),
        pipelineRunner: CommandPiping? = nil,
        clipboard: ClipboardWriting? = nil,
        destinationPlanner: LocalDestinationPlanner = LocalDestinationPlanner(),
        fileManager: FileManager = .default
    ) {
        self.runner = runner
        self.pipelineRunner = pipelineRunner ?? (runner as? CommandPiping) ?? ProcessCommandRunner()
        self.clipboard = clipboard ?? PBClipboardWriter(runner: runner)
        self.destinationPlanner = destinationPlanner
        self.fileManager = fileManager
    }

    public func download(
        remotePaths: [RemotePath],
        target: SSHTarget,
        destinationRoot: URL? = nil,
        copyToClipboard: Bool = true,
        progress: TransferProgressHandler? = nil,
        cancellation: TransferCancellation? = nil
    ) throws -> [DownloadedFile] {
        guard !remotePaths.isEmpty else {
            throw DownloadError.noRemotePaths
        }

        let root = destinationRoot ?? Self.defaultDestinationRoot()
        var downloaded: [DownloadedFile] = []

        for remotePath in remotePaths {
            try validate(remotePath: remotePath, target: target)
            let basename = (remotePath.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) as NSString).lastPathComponent
            guard !["", ".", "..", "~"].contains(basename), remotePath.path != "/" else {
                throw DownloadError.unsupportedRemotePath(remotePath.path)
            }
            let remoteKind = try inspect(remotePath: remotePath.path, target: target, cancellation: cancellation)
            let localKind = localDestinationKind(for: remoteKind)
            let fingerprint = try TransferIntegrity.remoteFingerprint(remotePath.path, target: target, runner: runner, cancellation: cancellation)
            if let existing = try matchingLocalPath(root: root, basename: basename, fingerprint: fingerprint, cancellation: cancellation) {
                guard try TransferIntegrity.remoteFingerprint(remotePath.path, target: target, runner: runner, cancellation: cancellation) == fingerprint else {
                    throw TransferIntegrityError.checksumMismatch(remotePath.path)
                }
                downloaded.append(DownloadedFile(remotePath: remotePath.path, localURL: existing, localDisplayPath: existing.path,
                                                 strategy: DownloadTransferPlanner.strategy(for: remoteKind), wasSkipped: true))
                continue
            }

            let key = TransferIntegrity.identifier([target.connectName, remotePath.path, fingerprint])
            let workspace = root.appendingPathComponent(".agent-drop-partial/" + key, isDirectory: true)
            let workspaceLock = try TransferWorkspaceLock(directory: workspace)
            defer { withExtendedLifetime(workspaceLock) {} }
            let payload = workspace.appendingPathComponent("payload", isDirectory: localKind == .directory)
            if localKind == .directory { try fileManager.createDirectory(at: payload, withIntermediateDirectories: true) }
            let staging = ReservedLocalDestination(url: payload, kind: localKind)

            let plan = DownloadTransferPlanner.plan(target: target, remotePath: remotePath.path, kind: remoteKind, reservedDestination: staging)
            try execute(plan, remotePath: remotePath.path, target: target, progress: progress, cancellation: cancellation)
            try TransferIntegrity.checkCancellation(cancellation)
            guard try TransferIntegrity.localFingerprint(payload, cancellation: cancellation) == fingerprint else {
                throw TransferIntegrityError.checksumMismatch(remotePath.path)
            }
            // Recheck the source so a changing file cannot be published as complete.
            guard try TransferIntegrity.remoteFingerprint(remotePath.path, target: target, runner: runner, cancellation: cancellation) == fingerprint else {
                throw TransferIntegrityError.checksumMismatch(remotePath.path)
            }
            let reserved: ReservedLocalDestination
            do {
                reserved = try destinationPlanner.reserve(root: root, remotePath: remotePath.path, kind: localKind)
            } catch let error as LocalDestinationPlannerError {
                throw destinationReservationError(from: error)
            }
            guard rename(payload.path, reserved.url.path) == 0 else {
                let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                try? reserved.cleanup(fileManager: fileManager)
                throw error
            }
            downloaded.append(DownloadedFile(remotePath: remotePath.path, localURL: reserved.url, localDisplayPath: reserved.url.path, strategy: plan.strategy))
        }

        if copyToClipboard {
            do {
                try clipboard.write(downloaded.map(\.localDisplayPath).joined(separator: "\n"))
            } catch {
                throw DownloadError.clipboardFailed(clipboardFailureReason(from: error))
            }
        }

        return downloaded
    }

    private func matchingLocalPath(root: URL, basename: String, fingerprint: String, cancellation: TransferCancellation?) throws -> URL? {
        for name in LocalNamePlanner(originalName: basename).candidates(prefixCount: 100) {
            let url = root.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: url.path) || (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil else { continue }
            if try TransferIntegrity.localFingerprint(url, cancellation: cancellation) == fingerprint { return url }
        }
        return nil
    }

    public static func defaultDestinationRoot(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent("Agent Drop", isDirectory: true)
    }

    public static func prepareDefaultDestinationRoot(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) throws -> URL {
        let root = defaultDestinationRoot(homeDirectory: homeDirectory)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func validate(remotePath: RemotePath, target: SSHTarget) throws {
        if let hostHint = remotePath.hostHint, hostHint != target.name, hostHint != target.connectName {
            throw DownloadError.hostHintMismatch(hostHint: hostHint, selectedTarget: target.connectName)
        }

        guard isSupportedRemotePath(remotePath.path) else {
            throw DownloadError.unsupportedRemotePath(remotePath.path)
        }
    }

    private func isSupportedRemotePath(_ path: String) -> Bool {
        path.hasPrefix("~/") || path.hasPrefix("/")
    }

    private func inspect(remotePath: String, target: SSHTarget, cancellation: TransferCancellation?) throws -> RemotePathKind {
        let invocation = DownloadTransferPlanner.remoteInspectionCommand(target: target, remotePath: remotePath)
        let result = try TransferIntegrity.run(invocation, runner: runner, cancellation: cancellation)
        guard result.succeeded else {
            throw DownloadError.remoteInspectionFailed(failureMessage(
                target: target,
                remotePath: remotePath,
                action: "inspection failed",
                result: result
            ))
        }

        return try parseInspection(stdout: result.stdout, remotePath: remotePath, target: target)
    }

    private func parseInspection(stdout: String, remotePath: String, target: SSHTarget) throws -> RemotePathKind {
        let lines = stdout.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        if lines == ["file", ""] {
            return .file
        }

        if lines.count == 3, lines[0] == "directory", lines[2] == "" {
            let countText = lines[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let count = Int(countText), count >= 0 else {
                throw DownloadError.remoteInspectionFailed(unrecognizedInspectionMessage(
                    target: target,
                    remotePath: remotePath,
                    stdout: stdout
                ))
            }
            return .directory(fileCount: count)
        }

        throw DownloadError.remoteInspectionFailed(unrecognizedInspectionMessage(
            target: target,
            remotePath: remotePath,
            stdout: stdout
        ))
    }

    private func localDestinationKind(for remoteKind: RemotePathKind) -> LocalDestinationKind {
        switch remoteKind {
        case .file:
            return .file
        case .directory:
            return .directory
        }
    }

    private func execute(
        _ plan: DownloadTransferPlan,
        remotePath: String,
        target: SSHTarget,
        progress: TransferProgressHandler?,
        cancellation: TransferCancellation?
    ) throws {
        switch plan.execution {
        case let .command(invocation):
            let result = try runRsync(invocation, progress: progress, cancellation: cancellation)
            guard result.succeeded else {
                throw DownloadError.rsyncFailed(failureMessage(
                    target: target,
                    remotePath: remotePath,
                    action: "transfer failed",
                    invocationDescription: invocation.executable,
                    result: result
                ))
            }
        case let .pipeline(remoteArchiveInvocation, localExtractInvocation):
            let result: CommandResult
            if let cancellablePipeline = pipelineRunner as? CancellableCommandPiping {
                result = try cancellablePipeline.runPipeline(
                    stdoutOf: remoteArchiveInvocation,
                    intoStdinOf: localExtractInvocation,
                    cancellation: cancellation
                )
            } else {
                result = try pipelineRunner.runPipeline(stdoutOf: remoteArchiveInvocation, intoStdinOf: localExtractInvocation)
            }
            guard result.succeeded else {
                throw DownloadError.tarFailed(failureMessage(
                    target: target,
                    remotePath: remotePath,
                    action: "tar pipeline failed",
                    invocationDescription: "\(remoteArchiveInvocation.executable) | \(localExtractInvocation.executable)",
                    result: result
                ))
            }
        }
    }

    private func runRsync(_ invocation: CommandInvocation, progress: TransferProgressHandler?, cancellation: TransferCancellation?) throws -> CommandResult {
        if let cancellableRunner = runner as? CancellableProgressReportingCommandRunning {
            let lineProgress: (@Sendable (String) -> Void)?
            if let handler = progress {
                lineProgress = { line in
                    if let parsed = RsyncProgressParser.parse(line) { handler(parsed) }
                }
            } else {
                lineProgress = nil
            }
            return try cancellableRunner.run(
                CommandInvocation(executable: invocation.executable, arguments: progress == nil ? invocation.arguments : ["--progress"] + invocation.arguments, standardInput: invocation.standardInput),
                progress: lineProgress,
                cancellation: cancellation
            )
        }

        guard let progress, let progressRunner = runner as? ProgressReportingCommandRunning else {
            return try runner.run(invocation)
        }

        let progressInvocation = CommandInvocation(
            executable: invocation.executable,
            arguments: ["--progress"] + invocation.arguments,
            standardInput: invocation.standardInput
        )
        return try progressRunner.run(progressInvocation) { line in
            if let parsed = RsyncProgressParser.parse(line) {
                progress(parsed)
            }
        }
    }

    private func failureMessage(
        target: SSHTarget,
        remotePath: String,
        action: String,
        invocationDescription: String? = nil,
        result: CommandResult
    ) -> String {
        let commandContext = invocationDescription.map { " using \($0)" } ?? ""
        return "target \(target.connectName) remote path \(remotePath) \(action) with exit code \(result.exitCode)\(commandContext): \(resultOutput(result))"
    }

    private func unrecognizedInspectionMessage(target: SSHTarget, remotePath: String, stdout: String) -> String {
        "target \(target.connectName) remote path \(remotePath) inspection produced unrecognized output: \(cleanOutput(stdout))"
    }

    private func resultOutput(_ result: CommandResult) -> String {
        let output = result.stderr.isEmpty ? result.stdout : result.stderr
        return cleanOutput(output)
    }

    private func cleanOutput(_ output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "<no output>" : trimmed
    }

    private func destinationReservationError(from error: LocalDestinationPlannerError) -> DownloadError {
        switch error {
        case let .invalidRemotePath(remotePath):
            return .unsupportedRemotePath(remotePath)
        case let .noAvailableLocalName(name):
            return .destinationReservationFailed(name)
        }
    }

    private func clipboardFailureReason(from error: Error) -> String {
        if case let ClipboardError.writeFailed(reason) = error {
            return reason
        }
        return String(describing: error)
    }
}
