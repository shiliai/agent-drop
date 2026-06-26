public enum CLICommand: Equatable {
    case targets
    case doctor
    case send(target: String?, paths: [String])
}

public enum CLIParseError: Error, Equatable {
    case empty
    case unknownCommand(String)
    case missingTargetValue
    case missingFiles
}

public enum CLIParser {
    public static func parse(_ arguments: [String]) throws -> CLICommand {
        guard let command = arguments.first else { throw CLIParseError.empty }

        switch command {
        case "targets":
            return .targets
        case "doctor":
            return .doctor
        case "send":
            return try parseSend(Array(arguments.dropFirst()))
        default:
            throw CLIParseError.unknownCommand(command)
        }
    }

    private static func parseSend(_ arguments: [String]) throws -> CLICommand {
        var target: String?
        var paths: [String] = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--target" {
                let valueIndex = index + 1
                guard valueIndex < arguments.count else { throw CLIParseError.missingTargetValue }
                target = arguments[valueIndex]
                index += 2
            } else {
                paths.append(argument)
                index += 1
            }
        }

        guard paths.isEmpty == false else { throw CLIParseError.missingFiles }
        return .send(target: target, paths: paths)
    }
}
