import Foundation

public enum RemotePathKind: Equatable {
    case file
    case directory(fileCount: Int)
}

public enum DownloadTransferStrategy: Equatable {
    case rsyncFile
    case rsyncDirectory
    case tarStream
}

public struct DownloadTransferPlan: Equatable {
    public let strategy: DownloadTransferStrategy
    public let invocations: [CommandInvocation]

    public init(strategy: DownloadTransferStrategy, invocations: [CommandInvocation]) {
        self.strategy = strategy
        self.invocations = invocations
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
        let invocations: [CommandInvocation]

        switch strategy {
        case .rsyncFile:
            invocations = [rsyncFileCommand(target: target, remotePath: remotePath, localURL: reservedDestination.url)]
        case .rsyncDirectory:
            invocations = [rsyncDirectoryCommand(target: target, remotePath: remotePath, localURL: reservedDestination.url)]
        case .tarStream:
            invocations = tarStreamCommands(target: target, remotePath: remotePath, localURL: reservedDestination.url)
        }

        return DownloadTransferPlan(strategy: strategy, invocations: invocations)
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

    public static func tarStreamCommands(target: SSHTarget, remotePath: String, localURL: URL) -> [CommandInvocation] {
        [
            CommandInvocation(
                executable: "/usr/bin/ssh",
                arguments: [target.connectName, "tar -C \(remoteShellPath(remotePath)) -czf - ."]
            ),
            CommandInvocation(
                executable: "/usr/bin/tar",
                arguments: ["-xzf", "-", "-C", localURL.path]
            )
        ]
    }

    private static func remoteShellPath(_ remotePath: String) -> String {
        if remotePath.hasPrefix("~/") {
            return ShellQuoting.homeRelativeCommandPath(String(remotePath.dropFirst(2)))
        }

        return ShellQuoting.singleQuote(remotePath)
    }
}
