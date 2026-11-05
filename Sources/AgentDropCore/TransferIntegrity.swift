import CryptoKit
import Darwin
import Foundation

public enum TransferIntegrityError: Error, Equatable {
    case checksumFailed(String)
    case checksumMismatch(String)
    case transferBusy
    case cancelled
}

/// Content checks and staging are independent of the Activity history.
enum TransferIntegrity {
    static let rsyncOptions = ["-a", "--checksum", "--partial"]

    static func checkCancellation(_ cancellation: TransferCancellation?) throws {
        if cancellation?.isCancelled == true { throw TransferIntegrityError.cancelled }
    }

    static func identifier(_ components: [String]) -> String {
        SHA256.hash(data: Data(components.joined(separator: "\0").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func shellPath(_ path: String) -> String {
        path.hasPrefix("~/") ? ShellQuoting.homeRelativeCommandPath(String(path.dropFirst(2))) : ShellQuoting.singleQuote(path)
    }

    static func localFingerprint(_ url: URL, cancellation: TransferCancellation?) throws -> String {
        let fileManager = FileManager.default
        func type(_ url: URL) throws -> FileAttributeType {
            try checkCancellation(cancellation)
            return try fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType ?? .typeUnknown
        }
        func hashFile(_ url: URL) throws -> String {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hash = SHA256()
            while true {
                try checkCancellation(cancellation)
                guard let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty else { break }
                hash.update(data: data)
            }
            return hex(hash.finalize())
        }
        func encodedLink(_ url: URL) throws -> String {
            Data((try fileManager.destinationOfSymbolicLink(atPath: url.path) + "\n").utf8).base64EncodedString()
        }
        switch try type(url) {
        case .typeRegular: return try hashFile(url)
        case .typeSymbolicLink:
            return hex(SHA256.hash(data: Data(("L\t" + (try encodedLink(url))).utf8)))
        case .typeDirectory:
            var records: [String] = []
            func visit(_ item: URL, path: String) throws {
                let name = Data(path.utf8).base64EncodedString()
                switch try type(item) {
                case .typeRegular: records.append("F\t\(name)\t\(try hashFile(item))\n")
                case .typeSymbolicLink: records.append("L\t\(name)\t\(try encodedLink(item))\n")
                case .typeDirectory:
                    records.append("D\t\(name)\n")
                    for child in try fileManager.contentsOfDirectory(atPath: item.path) {
                        try visit(item.appendingPathComponent(child), path: path + "/" + child)
                    }
                default: throw TransferIntegrityError.checksumFailed("Unsupported file type: \(item.path)")
                }
            }
            try visit(url, path: ".")
            var hash = SHA256()
            for record in records.sorted() {
                try checkCancellation(cancellation)
                hash.update(data: Data(record.utf8))
            }
            return hex(hash.finalize())
        default: throw TransferIntegrityError.checksumFailed("Unsupported file type: \(url.path)")
        }
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    static func remoteFingerprint(_ path: String, target: SSHTarget, runner: CommandRunning, cancellation: TransferCancellation?) throws -> String {
        let result = try run(CommandInvocation(
            executable: "/usr/bin/ssh",
            arguments: [target.connectName, "sh -c \(ShellQuoting.singleQuote(fingerprintScript)) sh \(shellPath(path))"]
        ), runner: runner, cancellation: cancellation)
        return try parseFingerprint(result)
    }

    static func run(_ invocation: CommandInvocation, runner: CommandRunning, cancellation: TransferCancellation?) throws -> CommandResult {
        try checkCancellation(cancellation)
        if let runner = runner as? CancellableProgressReportingCommandRunning {
            return try runner.run(invocation, progress: nil, cancellation: cancellation)
        }
        return try runner.run(invocation)
    }

    private static func parseFingerprint(_ result: CommandResult) throws -> String {
        let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.succeeded, value.count == 64, value.allSatisfy({ $0.isHexDigit && $0.isASCII }) else {
            throw TransferIntegrityError.checksumFailed(result.stderr.isEmpty ? "Invalid SHA-256 response" : result.stderr)
        }
        return value.lowercased()
    }

    // Matches the local manifest: filenames are base64 encoded before sorting;
    // failed reads and unsupported node types fail closed instead of yielding a partial manifest.
    static let fingerprintScript = #"""
    set -eu
    export LC_ALL=C
    if command -v sha256sum >/dev/null 2>&1; then
        hash() { sha256sum; }
    elif command -v shasum >/dev/null 2>&1; then
        hash() { shasum -a 256; }
    else
        echo 'SHA-256 tool (sha256sum or shasum) required' >&2; exit 1
    fi
    if [ ! -L "$1" ] && [ -f "$1" ]; then
        value=$(hash < "$1") || exit 1
        printf '%s\n' "${value%% *}"
        exit
    fi
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT HUP INT TERM
    emit='set -eu
    work=$1; shift
    for p do
        name=$(printf %s "$p" | base64 | tr -d "\n")
        if [ -L "$p" ]; then
            readlink "$p" > "$work/link-$$" || exit 1
            value=$(base64 < "$work/link-$$" | tr -d "\n")
            rm -f "$work/link-$$"
            printf "L\t%s\t%s\n" "$name" "$value"
        elif [ -f "$p" ]; then
            if command -v sha256sum >/dev/null 2>&1; then value=$(sha256sum < "$p"); else value=$(shasum -a 256 < "$p"); fi
            printf "F\t%s\t%s\n" "$name" "${value%% *}"
        elif [ -d "$p" ]; then
            printf "D\t%s\n" "$name"
        else
            echo "Unsupported file type" >&2; exit 1
        fi
    done'
    if [ -L "$1" ]; then
        # Root symlinks retain their target rather than hashing the referred file.
        readlink "$1" > "$work/link"
        printf 'L\t' > "$work/manifest"
        base64 < "$work/link" | tr -d '\n' >> "$work/manifest"
    elif [ -d "$1" ]; then
        cd "$1"
        find . -exec sh -c 'work=$1; emit=$2; shift 2; sh -c "$emit" sh "$work" "$@" || touch "$work/error"' sh "$work" "$emit" '{}' + > "$work/unsorted"
        test ! -e "$work/error"
        sort "$work/unsorted" > "$work/manifest"
    else
        echo 'Source does not exist' >&2; exit 1
    fi
    value=$(hash < "$work/manifest") || exit 1
    printf '%s\n' "${value%% *}"
    """#
}

/// Kernel-released lock: an interrupted process cannot strand a download lock.
final class TransferWorkspaceLock {
    private let descriptor: Int32

    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        descriptor = open(directory.appendingPathComponent("lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw TransferIntegrityError.transferBusy
        }
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
