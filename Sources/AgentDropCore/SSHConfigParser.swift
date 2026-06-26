import Foundation

public enum SSHTargetSource: String, Equatable, Codable, Sendable {
    case active
    case config
}

public struct SSHTarget: Equatable, Codable, Identifiable, Sendable {
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
            let trimmed = rawLine
                .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                .first?
                .trimmingCharacters(in: .whitespaces) ?? ""
            let fields = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard fields.first?.lowercased() == "host" else { continue }

            let names = fields.dropFirst()
                .filter { !$0.contains("*") && !$0.contains("?") && !$0.contains("!") }

            for name in names {
                targets.append(SSHTarget(name: name, source: .config))
            }
        }

        return targets
    }
}
