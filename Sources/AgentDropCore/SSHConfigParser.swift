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
            let fields = SSHConfigTokenizer.fields(in: String(rawLine))
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

enum SSHConfigTokenizer {
    static func fields(in line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var quote: Character?
        var isEscaping = false

        func finishField() {
            guard !current.isEmpty else { return }
            fields.append(current)
            current = ""
        }

        for character in line {
            if isEscaping {
                current.append(character)
                isEscaping = false
                continue
            }

            if character == "\\" {
                isEscaping = true
                continue
            }

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }

            if character == "\"" || character == "'" {
                quote = character
            } else if character == "#" {
                break
            } else if character == " " || character == "\t" {
                finishField()
            } else {
                current.append(character)
            }
        }

        if isEscaping {
            current.append("\\")
        }
        finishField()
        return fields
    }
}
