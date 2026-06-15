import Foundation

public struct ActiveSSHParser {
    public init() {}

    public func parseProcessCommands(_ commands: [String]) -> [SSHTarget] {
        commands.compactMap(parseCommand)
    }

    private func parseCommand(_ command: String) -> SSHTarget? {
        let tokens = tokenize(command)
        guard tokens.first.map(isSSHExecutable) == true else { return nil }

        var index = 1
        while index < tokens.count {
            let token = tokens[index]

            if ["-p", "-i", "-l", "-o", "-L", "-R", "-D", "-J"].contains(token) {
                index += 2
                continue
            }

            if token.hasPrefix("-") {
                index += 1
                continue
            }

            return SSHTarget(name: token, connectName: token, source: .active)
        }

        return nil
    }

    private func isSSHExecutable(_ token: String) -> Bool {
        token.split(separator: "/").last == "ssh"
    }

    private func tokenize(_ command: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var escaping = false

        for character in command {
            if escaping {
                current.append(character)
                escaping = false
                continue
            }

            if character == "\\" {
                escaping = true
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

            if character == "'" || character == "\"" {
                quote = character
                continue
            }

            if character == " " || character == "\t" {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }

            current.append(character)
        }

        if escaping {
            current.append("\\")
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }
}
