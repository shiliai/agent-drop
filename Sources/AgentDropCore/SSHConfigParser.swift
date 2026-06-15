import Foundation

public enum SSHTargetSource: String, Equatable, Codable {
    case active
    case config
}

public struct SSHTarget: Equatable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let connectName: String
    public let source: SSHTargetSource

    public init(name: String, connectName: String? = nil, source: SSHTargetSource) {
        self.id = connectName ?? name
        self.name = name
        self.connectName = connectName ?? name
        self.source = source
    }
}

public struct SSHConfigParser {
    public init() {}

    public func parse(_ text: String) -> [SSHTarget] {
        var targets: [SSHTarget] = []

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("host ") else { continue }

            let names = trimmed.dropFirst(5)
                .split(whereSeparator: { $0 == " " || $0 == "\t" })
                .map(String.init)
                .filter { !$0.contains("*") && !$0.contains("?") && !$0.contains("!") }

            for name in names {
                targets.append(SSHTarget(name: name, source: .config))
            }
        }

        return targets
    }
}
