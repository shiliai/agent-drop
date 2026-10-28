import Foundation

public struct UploadedFile: Equatable, Sendable {
    public let localURL: URL
    public let remoteDisplayPath: String
    public let localDisplayName: String

    public init(localURL: URL, remoteDisplayPath: String, localDisplayName: String? = nil) {
        self.localURL = localURL
        self.remoteDisplayPath = remoteDisplayPath
        self.localDisplayName = localDisplayName ?? localURL.lastPathComponent
    }
}

public struct UploadSourceFile: Codable, Equatable, Sendable {
    public let sourceURL: URL
    public let remoteName: String
    public let localDisplayName: String
    public let isDirectory: Bool

    public init(sourceURL: URL, remoteName: String, localDisplayName: String? = nil, isDirectory: Bool = false) {
        self.sourceURL = sourceURL
        self.remoteName = remoteName
        self.localDisplayName = localDisplayName ?? remoteName
        self.isDirectory = isDirectory
    }
}

public enum UploadError: Error, Equatable {
    case remoteDirectoryFailed(String)
    case noAvailableRemoteName(String)
    case remoteExistenceCheckFailed(String)
    case rsyncFailed(String)
    case clipboardFailed(String)
}

public final class UploadService {
    private let runner: CommandRunning
    private let clipboard: ClipboardWriting
    private let inboxPath: RemoteInboxPath

    public init(runner: CommandRunning = ProcessCommandRunner(), clipboard: ClipboardWriting? = nil, clock: Clock = SystemClock()) {
        self.runner = runner
        self.clipboard = clipboard ?? PBClipboardWriter(runner: runner)
        self.inboxPath = RemoteInboxPath(clock: clock)
    }

    public func upload(
        files: [URL],
        target: SSHTarget,
        copyToClipboard: Bool = true,
        progress: TransferProgressHandler? = nil,
        cancellation: TransferCancellation? = nil
    ) throws -> [UploadedFile] {
        try upload(
            sources: files.map {
                UploadSourceFile(
                    sourceURL: $0,
                    remoteName: $0.lastPathComponent,
                    isDirectory: Self.isDirectory($0)
                )
            },
            target: target,
            copyToClipboard: copyToClipboard,
            progress: progress,
            cancellation: cancellation
        )
    }

    public func upload(
        sources: [UploadSourceFile],
        target: SSHTarget,
        copyToClipboard: Bool = true,
        progress: TransferProgressHandler? = nil,
        cancellation: TransferCancellation? = nil
    ) throws -> [UploadedFile] {
        try createRemoteDirectory(target: target, cancellation: cancellation)

        var uploaded: [UploadedFile] = []

        for source in sources {
            let remoteName = try reserveRemoteName(for: source, target: target, cancellation: cancellation)
            let relativePath = inboxPath.relativeDirectory + "/" + remoteName
            let commandPath = ShellQuoting.homeRelativeCommandPath(relativePath) + (source.isDirectory ? "/" : "")
            let sourcePath = source.sourceURL.path + (source.isDirectory ? "/" : "")

            let result = try runRsync(CommandInvocation(
                executable: "/usr/bin/rsync",
                arguments: ["-a", sourcePath, "\(target.connectName):\(commandPath)"]
            ), progress: progress, cancellation: cancellation)

            guard result.succeeded else {
                removeReservedRemoteName(relativePath: relativePath, target: target, isDirectory: source.isDirectory)
                throw UploadError.rsyncFailed(result.stderr)
            }

            uploaded.append(UploadedFile(
                localURL: source.sourceURL,
                remoteDisplayPath: inboxPath.displayPath(forRemoteName: remoteName),
                localDisplayName: source.localDisplayName
            ))
        }

        if copyToClipboard {
            do {
                try clipboard.write(uploaded.map(\.remoteDisplayPath).joined(separator: "\n"))
            } catch {
                throw UploadError.clipboardFailed(clipboardFailureReason(from: error))
            }
        }

        return uploaded
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

    private func createRemoteDirectory(target: SSHTarget, cancellation: TransferCancellation?) throws {
        let commandPath = ShellQuoting.homeRelativeCommandPath(inboxPath.relativeDirectory)
        let result = try run(CommandInvocation(
            executable: "/usr/bin/ssh",
            arguments: [target.connectName, "mkdir -p -- \(commandPath)"]
        ), cancellation: cancellation)

        guard result.succeeded else {
            throw UploadError.remoteDirectoryFailed(result.stderr)
        }
    }

    private func reserveRemoteName(for source: UploadSourceFile, target: SSHTarget, cancellation: TransferCancellation?) throws -> String {
        for candidate in RemoteNamePlanner(originalName: source.remoteName).candidates(prefixCount: 100) {
            let relativePath = inboxPath.relativeDirectory + "/" + candidate
            let commandPath = ShellQuoting.homeRelativeCommandPath(relativePath)
            let reservationCommand = if source.isDirectory {
                "if mkdir \(commandPath) 2>/dev/null; then exit 0; fi; test -e \(commandPath) && exit 1; exit 2"
            } else {
                "if ( set -C; : > \(commandPath) ) 2>/dev/null; then exit 0; fi; test -e \(commandPath) && exit 1; exit 2"
            }
            let result = try run(CommandInvocation(
                executable: "/usr/bin/ssh",
                arguments: [target.connectName, reservationCommand]
            ), cancellation: cancellation)

            if result.exitCode == 0 {
                return candidate
            }

            if result.exitCode == 1 {
                continue
            }

            throw UploadError.remoteExistenceCheckFailed(result.stderr)
        }

        throw UploadError.noAvailableRemoteName(source.remoteName)
    }

    private func removeReservedRemoteName(relativePath: String, target: SSHTarget, isDirectory: Bool) {
        let commandPath = ShellQuoting.homeRelativeCommandPath(relativePath)
        let removeFlag = isDirectory ? "-rf" : "-f"
        _ = try? runner.run(CommandInvocation(
            executable: "/usr/bin/ssh",
            arguments: [target.connectName, "rm \(removeFlag) -- \(commandPath)"]
        ))
    }

    private func run(_ invocation: CommandInvocation, cancellation: TransferCancellation?) throws -> CommandResult {
        if let cancellableRunner = runner as? CancellableProgressReportingCommandRunning {
            return try cancellableRunner.run(invocation, progress: nil, cancellation: cancellation)
        }
        return try runner.run(invocation)
    }

    private func clipboardFailureReason(from error: Error) -> String {
        if case let ClipboardError.writeFailed(reason) = error {
            return reason
        }
        return String(describing: error)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
