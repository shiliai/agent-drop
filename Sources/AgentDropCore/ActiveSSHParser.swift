import Foundation

public struct ActiveSSHParser {
    public init() {}

    public func parseProcessCommands(_ commands: [String]) -> [SSHTarget] {
        commands.compactMap(parseCommand)
    }

    private func parseCommand(_ command: String) -> SSHTarget? {
        let tokens = command.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard tokens.first == "ssh" else { return nil }

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
}
