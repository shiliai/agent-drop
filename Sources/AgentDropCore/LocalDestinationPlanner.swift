import Darwin
import Foundation

public enum LocalDestinationKind: Equatable {
    case file
    case directory
}

public struct ReservedLocalDestination: Equatable {
    public let url: URL
    public let kind: LocalDestinationKind

    public init(url: URL, kind: LocalDestinationKind) {
        self.url = url
        self.kind = kind
    }

    public func cleanup(fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}

public enum LocalDestinationPlannerError: Error, Equatable {
    case invalidRemotePath(String)
    case noAvailableLocalName(String)
}

public struct LocalDestinationPlanner {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func reserve(root: URL, remotePath: String, kind: LocalDestinationKind) throws -> ReservedLocalDestination {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let basename = try remoteBasename(remotePath)
        for candidate in LocalNamePlanner(originalName: basename).candidates(prefixCount: 100) {
            let url = root.appendingPathComponent(candidate, isDirectory: kind == .directory)
            if try reserve(url: url, kind: kind) {
                return ReservedLocalDestination(url: url, kind: kind)
            }
        }

        throw LocalDestinationPlannerError.noAvailableLocalName(basename)
    }

    private func reserve(url: URL, kind: LocalDestinationKind) throws -> Bool {
        switch kind {
        case .file:
            return try reserveFile(url)
        case .directory:
            return try reserveDirectory(url)
        }
    }

    private func reserveFile(_ url: URL) throws -> Bool {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        if fd >= 0 {
            close(fd)
            return true
        }

        if errno == EEXIST {
            return false
        }

        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    private func reserveDirectory(_ url: URL) throws -> Bool {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
            return true
        } catch {
            if fileManager.fileExists(atPath: url.path) {
                return false
            }
            throw error
        }
    }

    private func remoteBasename(_ remotePath: String) throws -> String {
        let trimmed = String(remotePath.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        let basename = (trimmed as NSString).lastPathComponent

        guard !basename.isEmpty, basename != "." else {
            throw LocalDestinationPlannerError.invalidRemotePath(remotePath)
        }

        return basename
    }
}
