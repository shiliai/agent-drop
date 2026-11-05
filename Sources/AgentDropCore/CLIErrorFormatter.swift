public enum CLIErrorFormatter {
    public static func message(for error: Error) -> String {
        switch error {
        case CLIParseError.empty:
            return "No command provided."
        case let CLIParseError.unknownCommand(command):
            return "Unknown command '\(command)'."
        case CLIParseError.missingTargetValue:
            return "Missing value after --target."
        case CLIParseError.missingFiles:
            return "No paths provided."
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
        case let TransferIntegrityError.checksumFailed(reason):
            return "Could not verify SHA-256: \(reason)"
        case let TransferIntegrityError.checksumMismatch(path):
            return "SHA-256 verification failed for \(path). Retry the transfer."
        case TransferIntegrityError.transferBusy:
            return "This transfer is already running."
        case TransferIntegrityError.cancelled:
            return "Transfer cancelled. Partial data was retained for retry."
        default:
            return String(describing: error)
        }
    }
}
