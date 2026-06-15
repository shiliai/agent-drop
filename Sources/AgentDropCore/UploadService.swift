import Foundation

public struct UploadedFile: Equatable {
    public let localURL: URL
    public let remoteDisplayPath: String
}

public enum UploadError: Error, Equatable {
    case remoteDirectoryFailed(String)
    case noAvailableRemoteName(String)
    case remoteExistenceCheckFailed(String)
    case rsyncFailed(String)
    case clipboardFailed
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

    public func upload(files: [URL], target: SSHTarget) throws -> [UploadedFile] {
        try createRemoteDirectory(target: target)

        var uploaded: [UploadedFile] = []

        for file in files {
            let remoteName = try chooseRemoteName(for: file.lastPathComponent, target: target)
            let relativePath = inboxPath.relativeDirectory + "/" + remoteName
            let commandPath = ShellQuoting.homeRelativeCommandPath(relativePath)

            let result = try runner.run(CommandInvocation(
                executable: "/usr/bin/rsync",
                arguments: ["-a", file.path, "\(target.connectName):\(commandPath)"]
            ))

            guard result.succeeded else {
                throw UploadError.rsyncFailed(result.stderr)
            }

            uploaded.append(UploadedFile(localURL: file, remoteDisplayPath: inboxPath.displayPath(forRemoteName: remoteName)))
        }

        do {
            try clipboard.write(uploaded.map(\.remoteDisplayPath).joined(separator: "\n"))
        } catch {
            throw UploadError.clipboardFailed
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

    private func chooseRemoteName(for originalName: String, target: SSHTarget) throws -> String {
        for candidate in RemoteNamePlanner(originalName: originalName).candidates(prefixCount: 100) {
            let relativePath = inboxPath.relativeDirectory + "/" + candidate
            let commandPath = ShellQuoting.homeRelativeCommandPath(relativePath)
            let result = try runner.run(CommandInvocation(
                executable: "/usr/bin/ssh",
                arguments: [target.connectName, "test -e \(commandPath)"]
            ))

            if result.exitCode == 1 {
                return candidate
            }

            if result.exitCode != 0 {
                throw UploadError.remoteExistenceCheckFailed(result.stderr)
            }
        }

        throw UploadError.noAvailableRemoteName(originalName)
    }
}
