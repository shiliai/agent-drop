import Foundation

public enum FinderExtensionAvailabilityStatus: Equatable, Sendable {
    case enabled
    case disabled
    case notRegistered
    case unknown(String)

    public var needsSetup: Bool {
        switch self {
        case .enabled:
            return false
        case .disabled, .notRegistered, .unknown:
            return true
        }
    }
}

public struct FinderExtensionAvailability: Equatable, Sendable {
    public static let bundleIdentifier = "ai.shili.AgentDrop.FinderSync"
    public static let extensionPointIdentifier = "com.apple.FinderSync"

    public let bundleIdentifier: String
    public let status: FinderExtensionAvailabilityStatus

    public init(
        bundleIdentifier: String = FinderExtensionAvailability.bundleIdentifier,
        status: FinderExtensionAvailabilityStatus
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.status = status
    }

    public static func parse(
        pluginkitOutput: String,
        bundleIdentifier: String = FinderExtensionAvailability.bundleIdentifier
    ) -> FinderExtensionAvailability {
        for rawLine in pluginkitOutput.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard Self.bundleIdentifier(in: line) == bundleIdentifier else { continue }
            let status: FinderExtensionAvailabilityStatus = line.hasPrefix("+") ? .enabled : .disabled
            return FinderExtensionAvailability(bundleIdentifier: bundleIdentifier, status: status)
        }

        return FinderExtensionAvailability(bundleIdentifier: bundleIdentifier, status: .notRegistered)
    }

    private static func bundleIdentifier(in pluginkitLine: String) -> String? {
        let statusStrippedLine = pluginkitLine.hasPrefix("+")
            ? String(pluginkitLine.dropFirst()).trimmingCharacters(in: .whitespaces)
            : pluginkitLine

        guard let versionStart = statusStrippedLine.firstIndex(of: "(") else {
            return nil
        }

        return String(statusStrippedLine[..<versionStart]).trimmingCharacters(in: .whitespaces)
    }
}

public enum FinderExtensionAvailabilityChecker {
    public static func check(runner: CommandRunning = ProcessCommandRunner()) -> FinderExtensionAvailability {
        do {
            let result = try runner.run(CommandInvocation(
                executable: "/usr/bin/pluginkit",
                arguments: ["-m", "-A", "-p", FinderExtensionAvailability.extensionPointIdentifier]
            ))

            guard result.succeeded else {
                return FinderExtensionAvailability(status: .unknown(commandFailureMessage(from: result)))
            }

            return FinderExtensionAvailability.parse(pluginkitOutput: result.stdout)
        } catch {
            return FinderExtensionAvailability(status: .unknown(errorMessage(from: error)))
        }
    }

    private static func commandFailureMessage(from result: CommandResult) -> String {
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            return stderr
        }

        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stdout.isEmpty {
            return stdout
        }

        return "pluginkit exited with status \(result.exitCode)."
    }

    private static func errorMessage(from error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        let description = error.localizedDescription
        if !description.isEmpty {
            return description
        }

        return String(describing: error)
    }
}
