import Foundation

public struct UploadedFile: Equatable {
    public let localURL: URL
    public let remoteDisplayPath: String
    public let localDisplayName: String

    public init(localURL: URL, remoteDisplayPath: String, localDisplayName: String? = nil) {
        self.localURL = localURL
        self.remoteDisplayPath = remoteDisplayPath
        self.localDisplayName = localDisplayName ?? localURL.lastPathComponent
    }
}

public struct UploadSourceFile: Equatable {
    public let sourceURL: URL
    public let remoteName: String
    public let localDisplayName: String

    public init(sourceURL: URL, remoteName: String, localDisplayName: String? = nil) {
        self.sourceURL = sourceURL
        self.remoteName = remoteName
        self.localDisplayName = localDisplayName ?? remoteName
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

    public func upload(files: [URL], target: SSHTarget, copyToClipboard: Bool = true) throws -> [UploadedFile] {
        try upload(
            sources: files.map { UploadSourceFile(sourceURL: $0, remoteName: $0.lastPathComponent) },
            target: target,
            copyToClipboard: copyToClipboard
        )
    }

    public func upload(sources: [UploadSourceFile], target: SSHTarget, copyToClipboard: Bool = true) throws -> [UploadedFile] {
        try createRemoteDirectory(target: target)

        var uploaded: [UploadedFile] = []

        for source in sources {
            let remoteName = try reserveRemoteName(for: source.remoteName, target: target)
            let relativePath = inboxPath.relativeDirectory + "/" + remoteName
            let commandPath = ShellQuoting.homeRelativeCommandPath(relativePath)

            let result = try runner.run(CommandInvocation(
                executable: "/usr/bin/rsync",
                arguments: ["-a", source.sourceURL.path, "\(target.connectName):\(commandPath)"]
            ))

            guard result.succeeded else {
                removeReservedRemoteName(relativePath: relativePath, target: target)
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

    private func createRemoteDirectory(target: SSHTarget) throws {
        let commandPath = ShellQuoting.homeRelativeCommandPath(inboxPath.relativeDirectory)
        let result = try runner.run(CommandInvocation(
            executable: "/usr/bin/ssh",
            arguments: [target.connectName, "mkdir -p -- \(commandPath)"]
        ))

        guard result.succeeded else {
            throw UploadError.remoteDirectoryFailed(result.stderr)
        }
    }

    private func reserveRemoteName(for originalName: String, target: SSHTarget) throws -> String {
        for candidate in RemoteNamePlanner(originalName: originalName).candidates(prefixCount: 100) {
            let relativePath = inboxPath.relativeDirectory + "/" + candidate
            let commandPath = ShellQuoting.homeRelativeCommandPath(relativePath)
            let result = try runner.run(CommandInvocation(
                executable: "/usr/bin/ssh",
                arguments: [target.connectName, "if ( set -C; : > \(commandPath) ) 2>/dev/null; then exit 0; fi; test -e \(commandPath) && exit 1; exit 2"]
            ))

            if result.exitCode == 0 {
                return candidate
            }

            if result.exitCode == 1 {
                continue
            }

            throw UploadError.remoteExistenceCheckFailed(result.stderr)
        }

        throw UploadError.noAvailableRemoteName(originalName)
    }

    private func removeReservedRemoteName(relativePath: String, target: SSHTarget) {
        let commandPath = ShellQuoting.homeRelativeCommandPath(relativePath)
        _ = try? runner.run(CommandInvocation(
            executable: "/usr/bin/ssh",
            arguments: [target.connectName, "rm -f -- \(commandPath)"]
        ))
    }

    private func clipboardFailureReason(from error: Error) -> String {
        if case let ClipboardError.writeFailed(reason) = error {
            return reason
        }
        return String(describing: error)
    }
}
