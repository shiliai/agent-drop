import Foundation

public struct CommandInvocation: Equatable {
    public let executable: String
    public let arguments: [String]
    public let standardInput: String?

    public init(executable: String, arguments: [String], standardInput: String? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.standardInput = standardInput
    }
}

public struct CommandResult: Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public static func success(stdout: String, stderr: String) -> CommandResult {
        CommandResult(exitCode: 0, stdout: stdout, stderr: stderr)
    }

    public static func failure(exitCode: Int32, stdout: String, stderr: String) -> CommandResult {
        CommandResult(exitCode: exitCode, stdout: stdout, stderr: stderr)
    }

    public var succeeded: Bool { exitCode == 0 }
}

public protocol CommandRunning {
    func run(_ invocation: CommandInvocation) throws -> CommandResult
}

public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(_ invocation: CommandInvocation) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = invocation.arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let input = invocation.standardInput.map { _ in Pipe() }
        if let input {
            process.standardInput = input
        }

        try process.run()

        let stdoutCapture = ProcessOutputCapture()
        let stderrCapture = ProcessOutputCapture()
        let stdoutQueue = DispatchQueue(label: "agent-drop.command-runner.stdout")
        let stderrQueue = DispatchQueue(label: "agent-drop.command-runner.stderr")
        let outputGroup = DispatchGroup()

        outputGroup.enter()
        stdoutQueue.async {
            stdoutCapture.data = stdout.fileHandleForReading.readDataToEndOfFile()
            outputGroup.leave()
        }

        outputGroup.enter()
        stderrQueue.async {
            stderrCapture.data = stderr.fileHandleForReading.readDataToEndOfFile()
            outputGroup.leave()
        }

        if let standardInput = invocation.standardInput, let input {
            if let data = standardInput.data(using: .utf8) {
                input.fileHandleForWriting.write(data)
            }
            input.fileHandleForWriting.closeFile()
        }

        process.waitUntilExit()
        outputGroup.wait()

        let out = String(data: stdoutCapture.data, encoding: .utf8) ?? ""
        let err = String(data: stderrCapture.data, encoding: .utf8) ?? ""
        return CommandResult(exitCode: process.terminationStatus, stdout: out, stderr: err)
    }
}

private final class ProcessOutputCapture: @unchecked Sendable {
    var data = Data()
}

public protocol ClipboardWriting {
    func write(_ text: String) throws
}

public enum ClipboardError: Error, Equatable {
    case writeFailed(String)
}

public struct PBClipboardWriter: ClipboardWriting {
    private let runner: CommandRunning

    public init(runner: CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    public func write(_ text: String) throws {
        let result = try runner.run(CommandInvocation(executable: "/usr/bin/pbcopy", arguments: [], standardInput: text))
        guard result.succeeded else {
            throw ClipboardError.writeFailed(result.stderr)
        }
    }
}
