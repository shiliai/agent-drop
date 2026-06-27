import Foundation

public enum DoctorStatus: Equatable {
    case ok
    case missing
}

public struct DoctorCheck: Equatable {
    public let name: String
    public let status: DoctorStatus
}

public struct DoctorReport: Equatable {
    public let checks: [DoctorCheck]
}

public enum DependencyRequirement {
    case finderUpload
    case appPull

    public var requiredToolNames: [String] {
        switch self {
        case .finderUpload:
            return ["ssh", "rsync"]
        case .appPull:
            return ["ssh", "rsync", "tar", "pbcopy"]
        }
    }
}

public struct DependencyFeedback: Equatable {
    public let missingToolNames: [String]

    public init(missingToolNames: [String]) {
        self.missingToolNames = missingToolNames
    }

    public var message: String {
        let toolList = missingToolNames.joined(separator: ", ")
        let noun = missingToolNames.count == 1 ? "tool" : "tools"
        let pronoun = missingToolNames.count == 1 ? "it" : "them"
        return "Missing required local \(noun): \(toolList). Install \(pronoun) and try again. Agent Drop does not install dependencies automatically."
    }

    public static func missingFeedback(in report: DoctorReport, for requirement: DependencyRequirement) -> DependencyFeedback? {
        let required = Set(requirement.requiredToolNames)
        let missing = report.checks
            .filter { required.contains($0.name) && $0.status == .missing }
            .map(\.name)

        guard !missing.isEmpty else { return nil }
        return DependencyFeedback(missingToolNames: missing)
    }
}

public struct Doctor {
    private let toolLookup: (String) -> String?

    public init(toolLookup: @escaping (String) -> String? = Doctor.defaultLookup) {
        self.toolLookup = toolLookup
    }

    public func run() -> DoctorReport {
        let checks = ["ssh", "rsync", "tar", "pbcopy"].map { tool in
            DoctorCheck(name: tool, status: toolLookup(tool) == nil ? .missing : .ok)
        }
        return DoctorReport(checks: checks)
    }

    @usableFromInline
    static func defaultLookup(_ tool: String) -> String? {
        ["/usr/bin/\(tool)", "/bin/\(tool)", "/opt/homebrew/bin/\(tool)"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }
}
