import Foundation

public struct DownloadedFile: Equatable {
    public let remotePath: String
    public let localURL: URL
    public let localDisplayPath: String
    public let strategy: DownloadTransferStrategy

    public init(remotePath: String, localURL: URL, localDisplayPath: String, strategy: DownloadTransferStrategy) {
        self.remotePath = remotePath
        self.localURL = localURL
        self.localDisplayPath = localDisplayPath
        self.strategy = strategy
    }
}

public enum DownloadError: Error, Equatable {
    case noRemotePaths
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
        copyToClipboard: Bool = true
    ) throws -> [DownloadedFile] {
        guard !remotePaths.isEmpty else {
            throw DownloadError.noRemotePaths
        }

        let root = destinationRoot ?? Self.defaultDestinationRoot()
        var downloaded: [DownloadedFile] = []

        for remotePath in remotePaths {
            let remoteKind = try inspect(remotePath: remotePath.path, target: target)
            let localKind = localDestinationKind(for: remoteKind)
            let reserved: ReservedLocalDestination

            do {
                reserved = try destinationPlanner.reserve(root: root, remotePath: remotePath.path, kind: localKind)
            } catch let error as LocalDestinationPlannerError {
                throw destinationReservationError(from: error)
            } catch {
                throw DownloadError.destinationReservationFailed(String(describing: error))
            }

            do {
                let plan = DownloadTransferPlanner.plan(
                    target: target,
                    remotePath: remotePath.path,
                    kind: remoteKind,
                    reservedDestination: reserved
                )
                try execute(plan)
                downloaded.append(DownloadedFile(
                    remotePath: remotePath.path,
                    localURL: reserved.url,
                    localDisplayPath: reserved.url.path,
                    strategy: plan.strategy
                ))
            } catch {
                try? reserved.cleanup(fileManager: fileManager)
                throw error
            }
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

    private static func defaultDestinationRoot() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent("Agent Drop", isDirectory: true)
    }

    private func inspect(remotePath: String, target: SSHTarget) throws -> RemotePathKind {
        let result = try runner.run(DownloadTransferPlanner.remoteInspectionCommand(target: target, remotePath: remotePath))
        guard result.succeeded else {
            throw DownloadError.remoteInspectionFailed(result.stderr)
        }

        return try parseInspection(stdout: result.stdout)
    }

    private func parseInspection(stdout: String) throws -> RemotePathKind {
        let lines = stdout.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        if lines == ["file", ""] {
            return .file
        }

        if lines.count == 3, lines[0] == "directory", lines[2] == "" {
            let countText = lines[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let count = Int(countText), count >= 0 else {
                throw DownloadError.remoteInspectionFailed(stdout)
            }
            return .directory(fileCount: count)
        }

        throw DownloadError.remoteInspectionFailed(stdout)
    }

    private func localDestinationKind(for remoteKind: RemotePathKind) -> LocalDestinationKind {
        switch remoteKind {
        case .file:
            return .file
        case .directory:
            return .directory
        }
    }

    private func execute(_ plan: DownloadTransferPlan) throws {
        switch plan.execution {
        case let .command(invocation):
            let result = try runner.run(invocation)
            guard result.succeeded else {
                throw DownloadError.rsyncFailed(result.stderr)
            }
        case let .pipeline(remoteArchiveInvocation, localExtractInvocation):
            let result = try pipelineRunner.runPipeline(stdoutOf: remoteArchiveInvocation, intoStdinOf: localExtractInvocation)
            guard result.succeeded else {
                throw DownloadError.tarFailed(result.stderr)
            }
        }
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
