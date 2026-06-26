import Foundation

public enum RemotePathKind: Equatable, Sendable {
    case file
    case directory(fileCount: Int)
}

public enum DownloadTransferStrategy: Equatable, Sendable {
    case rsyncFile
    case rsyncDirectory
    case tarStream
}

public enum DownloadTransferExecution: Equatable, Sendable {
    case command(CommandInvocation)
    case pipeline(remoteArchiveInvocation: CommandInvocation, localExtractInvocation: CommandInvocation)
}

public struct DownloadTransferPlan: Equatable, Sendable {
    public let strategy: DownloadTransferStrategy
    public let execution: DownloadTransferExecution

    public init(strategy: DownloadTransferStrategy, execution: DownloadTransferExecution) {
        self.strategy = strategy
        self.execution = execution
    }
}

public enum DownloadTransferPlanner {
    public static let tarFileCountThreshold = 200

    public static func remoteInspectionCommand(target: SSHTarget, remotePath: String) -> CommandInvocation {
        let commandPath = remoteShellPath(remotePath)
        let command = "if [ -f \(commandPath) ]; then printf 'file\\n'; elif [ -d \(commandPath) ]; then printf 'directory\\n'; find \(commandPath) -type f | wc -l; else exit 2; fi"
        return CommandInvocation(
            executable: "/usr/bin/ssh",
            arguments: [target.connectName, command]
        )
    }

    public static func strategy(for kind: RemotePathKind) -> DownloadTransferStrategy {
        switch kind {
        case .file:
            return .rsyncFile
        case let .directory(fileCount):
            return fileCount > tarFileCountThreshold ? .tarStream : .rsyncDirectory
        }
    }

    public static func plan(
        target: SSHTarget,
        remotePath: String,
        kind: RemotePathKind,
        reservedDestination: ReservedLocalDestination
    ) -> DownloadTransferPlan {
        let strategy = strategy(for: kind)
        let execution: DownloadTransferExecution

        switch strategy {
        case .rsyncFile:
            execution = .command(rsyncFileCommand(target: target, remotePath: remotePath, localURL: reservedDestination.url))
        case .rsyncDirectory:
            execution = .command(rsyncDirectoryCommand(target: target, remotePath: remotePath, localURL: reservedDestination.url))
        case .tarStream:
            let pipeline = tarStreamPipeline(target: target, remotePath: remotePath, localURL: reservedDestination.url)
            execution = .pipeline(
                remoteArchiveInvocation: pipeline.remoteArchiveInvocation,
                localExtractInvocation: pipeline.localExtractInvocation
            )
        }

        return DownloadTransferPlan(strategy: strategy, execution: execution)
    }

    public static func rsyncFileCommand(target: SSHTarget, remotePath: String, localURL: URL) -> CommandInvocation {
        CommandInvocation(
            executable: "/usr/bin/rsync",
            arguments: ["-a", "\(target.connectName):\(remoteShellPath(remotePath))", localURL.path]
        )
    }

    public static func rsyncDirectoryCommand(target: SSHTarget, remotePath: String, localURL: URL) -> CommandInvocation {
        CommandInvocation(
            executable: "/usr/bin/rsync",
            arguments: ["-a", "\(target.connectName):\(remoteShellPath(remotePath))/", localURL.path + "/"]
        )
    }

    public static func tarStreamPipeline(
        target: SSHTarget,
        remotePath: String,
        localURL: URL
    ) -> (remoteArchiveInvocation: CommandInvocation, localExtractInvocation: CommandInvocation) {
        (
            remoteArchiveInvocation: CommandInvocation(
                executable: "/usr/bin/ssh",
                arguments: [target.connectName, "tar -C \(remoteShellPath(remotePath)) -czf - ."]
            ),
            localExtractInvocation: CommandInvocation(
                executable: "/usr/bin/tar",
                arguments: ["-xzf", "-", "-C", localURL.path]
            )
        )
    }

    private static func remoteShellPath(_ remotePath: String) -> String {
        if remotePath.hasPrefix("~/") {
            return ShellQuoting.homeRelativeCommandPath(String(remotePath.dropFirst(2)))
        }

        return ShellQuoting.singleQuote(remotePath)
    }
}
