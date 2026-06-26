import Foundation

public struct RemotePath: Equatable, Sendable {
    public let hostHint: String?
    public let path: String

    public init(hostHint: String?, path: String) {
        self.hostHint = hostHint
        self.path = path
    }
}

public enum RemotePathParserError: Error, Equatable, Sendable {
    case noPaths
    case unsupportedRelativePath(String)
}

public enum RemotePathParser {
    public static func parse(_ input: String) throws -> [RemotePath] {
        let lines = input
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            throw RemotePathParserError.noPaths
        }

        return try lines.map(parseLine)
    }

    private static func parseLine(_ line: String) throws -> RemotePath {
        if isSupportedRemotePath(line) {
            return RemotePath(hostHint: nil, path: line)
        }

        if let colonIndex = line.firstIndex(of: ":") {
            let host = String(line[..<colonIndex])
            let pathStart = line.index(after: colonIndex)
            let path = String(line[pathStart...])

            guard !host.isEmpty, isSupportedRemotePath(path) else {
                throw RemotePathParserError.unsupportedRelativePath(line)
            }

            return RemotePath(hostHint: host, path: path)
        }
        throw RemotePathParserError.unsupportedRelativePath(line)
    }

    private static func isSupportedRemotePath(_ value: String) -> Bool {
        value.hasPrefix("~/") || value.hasPrefix("/")
    }
}
