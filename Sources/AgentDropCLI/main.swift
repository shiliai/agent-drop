import AgentDropCore
import Darwin
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())

do {
    let command = try CLIParser.parse(arguments)
    let runner = ProcessCommandRunner()

    switch command {
    case .targets:
        let targets = discoverTargets(runner: runner)
        for target in targets {
            print("\(target.name)\t\(target.source.rawValue)")
        }

    case .doctor:
        let report = Doctor().run()
        for check in report.checks {
            print("\(check.name): \(check.status == .ok ? "ok" : "missing")")
        }

    case let .send(targetName, paths):
        let targets = discoverTargets(runner: runner)
        guard let target = resolveTarget(named: targetName, from: targets) else {
            fputs("No SSH target selected or found.\n", stderr)
            exit(2)
        }

        let urls = paths.map { URL(fileURLWithPath: $0) }
        let selection = FileSelection.validate(urls)
        let selectionErrors = FileSelection.cliFailureMessages(for: selection)
        guard selectionErrors.isEmpty else {
            for message in selectionErrors {
                fputs("\(message)\n", stderr)
            }
            exit(3)
        }

        let uploaded = try UploadService(runner: runner).upload(files: selection.files, target: target)
        for file in uploaded {
            print(file.remoteDisplayPath)
        }

    case let .pull(targetName, paths):
        let targets = discoverTargets(runner: runner)
        guard let target = resolveTarget(named: targetName, from: targets) else {
            fputs("No SSH target selected or found.\n", stderr)
            exit(2)
        }

        let remotePaths = try parseRemotePathArguments(paths)
        let downloaded = try DownloadService(runner: runner).download(remotePaths: remotePaths, target: target)
        for file in downloaded {
            print(file.localDisplayPath)
        }
    }
} catch {
    fputs("agent-drop: \(cliErrorMessage(for: error))\n", stderr)
    exit(1)
}

private func parseRemotePathArguments(_ arguments: [String]) throws -> [RemotePath] {
    try arguments.flatMap { try RemotePathParser.parse($0) }
}

private func cliErrorMessage(for error: Error) -> String {
    switch error {
    case RemotePathParserError.noPaths:
        return "No remote paths provided."
    case let RemotePathParserError.unsupportedRelativePath(path):
        return "Unsupported remote path '\(path)'. Use ~/path or /absolute/path."
    case DownloadError.noRemotePaths:
        return "No remote paths provided."
    case let DownloadError.hostHintMismatch(hostHint, selectedTarget):
        return "Remote path host '\(hostHint)' does not match selected target '\(selectedTarget)'."
    case let DownloadError.remoteInspectionFailed(reason):
        return reason
    case let DownloadError.unsupportedRemotePath(path):
        return "Unsupported remote path '\(path)'. Use ~/path or /absolute/path."
    case let DownloadError.destinationReservationFailed(reason):
        return "Could not reserve local destination: \(reason)"
    case let DownloadError.rsyncFailed(reason):
        return reason
    case let DownloadError.tarFailed(reason):
        return reason
    case let DownloadError.clipboardFailed(reason):
        return "Downloaded files, but could not copy local paths: \(reason)"
    default:
        return String(describing: error)
    }
}

private func discoverTargets(runner: CommandRunning) -> [SSHTarget] {
    let configText = (try? String(contentsOfFile: NSString(string: "~/.ssh/config").expandingTildeInPath)) ?? ""
    let configured = SSHConfigParser().parse(configText)

    let ps = (try? runner.run(CommandInvocation(executable: "/bin/ps", arguments: ["-axo", "command"])))?.stdout ?? ""
    let active = ActiveSSHParser().parseProcessCommands(ps.split(separator: "\n").map(String.init))

    return TargetResolver.merge(active: active, configured: configured)
}

private func resolveTarget(named name: String?, from targets: [SSHTarget]) -> SSHTarget? {
    if let name {
        return targets.first { $0.name == name || $0.connectName == name } ?? SSHTarget(name: name, connectName: name, source: .config)
    }

    if targets.count == 1 {
        return targets[0]
    }

    return nil
}
