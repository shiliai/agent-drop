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

public struct Doctor {
    private let toolLookup: (String) -> String?

    public init(toolLookup: @escaping (String) -> String? = Doctor.defaultLookup) {
        self.toolLookup = toolLookup
    }

    public func run() -> DoctorReport {
        let checks = ["ssh", "rsync", "pbcopy"].map { tool in
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
