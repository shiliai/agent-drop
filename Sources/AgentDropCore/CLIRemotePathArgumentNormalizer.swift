import Foundation

public struct CLIRemotePathArgumentNormalizer {
    private let localHomeDirectory: String

    public init(localHomeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        self.localHomeDirectory = localHomeDirectory
    }

    public func normalize(_ argument: String) -> String {
        argument
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { normalizeLine(String($0)) }
            .joined(separator: "\n")
    }

    private func normalizeLine(_ line: String) -> String {
        guard !hasHostHint(line) else {
            return line
        }

        if line == localHomeDirectory {
            return "~"
        }

        let homePrefix = localHomeDirectory + "/"
        guard line.hasPrefix(homePrefix) else {
            return line
        }

        return "~/" + line.dropFirst(homePrefix.count)
    }

    private func hasHostHint(_ line: String) -> Bool {
        guard let colon = line.firstIndex(of: ":") else {
            return false
        }

        if let slash = line.firstIndex(of: "/") {
            return colon < slash
        }

        return true
    }
}
