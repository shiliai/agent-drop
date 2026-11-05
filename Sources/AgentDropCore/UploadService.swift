import Foundation

public struct UploadedFile: Equatable, Sendable {
    public let localURL: URL
    public let remoteDisplayPath: String
    public let localDisplayName: String
    public let wasSkipped: Bool

    public init(localURL: URL, remoteDisplayPath: String, localDisplayName: String? = nil, wasSkipped: Bool = false) {
        self.localURL = localURL
        self.remoteDisplayPath = remoteDisplayPath
        self.localDisplayName = localDisplayName ?? localURL.lastPathComponent
        self.wasSkipped = wasSkipped
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
            guard !source.remoteName.isEmpty, source.remoteName != ".", source.remoteName != "..", !source.remoteName.contains("/") else {
                throw UploadError.noAvailableRemoteName(source.remoteName)
            }
            try TransferIntegrity.checkCancellation(cancellation)
            let fingerprint = try TransferIntegrity.localFingerprint(source.sourceURL, cancellation: cancellation)
            if let existing = try matchingRemotePath(source: source, fingerprint: fingerprint, target: target, cancellation: cancellation) {
                uploaded.append(UploadedFile(localURL: source.sourceURL, remoteDisplayPath: "~/" + existing, localDisplayName: source.localDisplayName, wasSkipped: true))
                continue
            }

            let key = TransferIntegrity.identifier([source.remoteName, fingerprint])
            let stagingPath = ".agent-inbox/.partial/" + key
            let payload = stagingPath + "/payload"
            let stagingCommand = ShellQuoting.homeRelativeCommandPath(stagingPath)
            let payloadCommand = ShellQuoting.homeRelativeCommandPath(payload)
            let prepare = source.isDirectory ? "mkdir -p -- \(payloadCommand)" : "mkdir -p -- \(stagingCommand)"
            let prepared = try run(CommandInvocation(executable: "/usr/bin/ssh", arguments: [target.connectName, prepare]), cancellation: cancellation)
            guard prepared.succeeded else { throw UploadError.remoteDirectoryFailed(prepared.stderr) }
            let commandPath = payloadCommand + (source.isDirectory ? "/" : "")
            let sourcePath = source.sourceURL.path + (source.isDirectory ? "/" : "")

            let result = try runRsync(CommandInvocation(
                executable: "/usr/bin/rsync",
                arguments: TransferIntegrity.rsyncOptions + [sourcePath, "\(target.connectName):\(commandPath)"]
            ), progress: progress, cancellation: cancellation)

            guard result.succeeded else {
                throw UploadError.rsyncFailed(result.stderr)
            }

            try TransferIntegrity.checkCancellation(cancellation)
            let received = try TransferIntegrity.remoteFingerprint("~/" + payload, target: target, runner: runner, cancellation: cancellation)
            guard received == fingerprint else { throw TransferIntegrityError.checksumMismatch(source.localDisplayName) }
            guard try TransferIntegrity.localFingerprint(source.sourceURL, cancellation: cancellation) == fingerprint else {
                throw TransferIntegrityError.checksumMismatch(source.localDisplayName)
            }
            let remoteName = try reserveRemoteName(for: source, target: target, cancellation: cancellation)
            let relativePath = inboxPath.relativeDirectory + "/" + remoteName
            let destination = ShellQuoting.homeRelativeCommandPath(relativePath)
            let publish = source.isDirectory ? "rmdir -- \(destination) && mv -- \(payloadCommand) \(destination)" : "mv -f -- \(payloadCommand) \(destination)"
            let published = try run(CommandInvocation(executable: "/usr/bin/ssh", arguments: [target.connectName, publish]), cancellation: cancellation)
            guard published.succeeded else {
                removeReservedRemoteName(relativePath: relativePath, target: target, isDirectory: source.isDirectory)
                throw UploadError.rsyncFailed(published.stderr)
            }
            guard try TransferIntegrity.remoteFingerprint("~/" + relativePath, target: target, runner: runner, cancellation: cancellation) == fingerprint else {
                throw TransferIntegrityError.checksumMismatch(source.localDisplayName)
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

    private func matchingRemotePath(source: UploadSourceFile, fingerprint: String, target: SSHTarget, cancellation: TransferCancellation?) throws -> String? {
        let names = RemoteNamePlanner(originalName: source.remoteName).candidates(prefixCount: 100).map(ShellQuoting.singleQuote).joined(separator: " ")
        let command = "for d in \"$HOME\"/.agent-inbox/????-??-??; do [ -d \"$d\" ] || continue; for n in \(names); do p=\"$d/$n\"; if [ -e \"$p\" ] || [ -L \"$p\" ]; then printf %s \"${p#\"$HOME/\"}\" | base64 | tr -d '\\n'; printf '\\n'; fi; done; done"
        let result = try run(CommandInvocation(executable: "/usr/bin/ssh", arguments: [target.connectName, command]), cancellation: cancellation)
        guard result.succeeded else { throw UploadError.remoteExistenceCheckFailed(result.stderr) }
        for encoded in result.stdout.split(separator: "\n") {
            guard let data = Data(base64Encoded: String(encoded)), let path = String(data: data, encoding: .utf8),
                  path.hasPrefix(".agent-inbox/"), !path.split(separator: "/").contains("..") else {
                throw UploadError.remoteExistenceCheckFailed("Invalid inbox path response")
            }
            let actual = try TransferIntegrity.remoteFingerprint("~/" + path, target: target, runner: runner, cancellation: cancellation)
            if actual == fingerprint { return path }
        }
        return nil
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
        let cleanup = isDirectory ? "rmdir -- \(commandPath)" : "if [ ! -L \(commandPath) ] && [ -f \(commandPath) ] && [ ! -s \(commandPath) ]; then rm -f -- \(commandPath); fi"
        _ = try? runner.run(CommandInvocation(
            executable: "/usr/bin/ssh",
            arguments: [target.connectName, cleanup]
        ))
    }

    private func run(_ invocation: CommandInvocation, cancellation: TransferCancellation?) throws -> CommandResult {
        try TransferIntegrity.run(invocation, runner: runner, cancellation: cancellation)
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
