import Foundation

public struct CommandInvocation: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
    public let standardInput: String?

    public init(executable: String, arguments: [String], standardInput: String? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.standardInput = standardInput
    }
}

public struct CommandResult: Equatable, Sendable {
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

public protocol ProgressReportingCommandRunning: CommandRunning {
    func run(
        _ invocation: CommandInvocation,
        progress: (@Sendable (String) -> Void)?
    ) throws -> CommandResult
}

public protocol CommandPiping {
    func runPipeline(stdoutOf producer: CommandInvocation, intoStdinOf consumer: CommandInvocation) throws -> CommandResult
}

public struct ProcessCommandRunner: CommandRunning, ProgressReportingCommandRunning, CommandPiping {
    private let environment: [String: String]?

    public init(environment: [String: String]? = nil) {
        self.environment = environment
    }

    public func run(_ invocation: CommandInvocation) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = invocation.arguments
        applyEnvironment(to: process)

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

    public func run(
        _ invocation: CommandInvocation,
        progress: (@Sendable (String) -> Void)?
    ) throws -> CommandResult {
        guard let progress else {
            return try run(invocation)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = invocation.arguments
        applyEnvironment(to: process)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let input = invocation.standardInput.map { _ in Pipe() }
        if let input {
            process.standardInput = input
        }

        let stderrState = StreamingStderrState()
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(data: data, encoding: .utf8) ?? ""
            let completeLines = stderrState.append(data: data, text: text)

            for line in completeLines {
                progress(String(line).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        let stdoutCapture = ProcessOutputCapture()
        let stdoutQueue = DispatchQueue(label: "agent-drop.command-runner.progress.stdout")
        let stdoutGroup = DispatchGroup()
        stdoutGroup.enter()
        stdoutQueue.async {
            stdoutCapture.data = stdout.fileHandleForReading.readDataToEndOfFile()
            stdoutGroup.leave()
        }

        try process.run()

        if let standardInput = invocation.standardInput, let input {
            if let data = standardInput.data(using: .utf8) {
                input.fileHandleForWriting.write(data)
            }
            input.fileHandleForWriting.closeFile()
        }

        process.waitUntilExit()
        stderr.fileHandleForReading.readabilityHandler = nil
        let remainder = stderr.fileHandleForReading.readDataToEndOfFile()
        let finalLine = stderrState.appendRemainder(remainder)
        if !finalLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            progress(finalLine.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        stdoutGroup.wait()

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutCapture.data, encoding: .utf8) ?? "",
            stderr: String(data: stderrState.data, encoding: .utf8) ?? ""
        )
    }

    public func runPipeline(stdoutOf producerInvocation: CommandInvocation, intoStdinOf consumerInvocation: CommandInvocation) throws -> CommandResult {
        let producer = Process()
        producer.executableURL = URL(fileURLWithPath: producerInvocation.executable)
        producer.arguments = producerInvocation.arguments

        let consumer = Process()
        consumer.executableURL = URL(fileURLWithPath: consumerInvocation.executable)
        consumer.arguments = consumerInvocation.arguments
        applyEnvironment(to: producer)
        applyEnvironment(to: consumer)

        let archivePipe = Pipe()
        producer.standardOutput = archivePipe
        consumer.standardInput = archivePipe

        let producerStderr = Pipe()
        let consumerStdout = Pipe()
        let consumerStderr = Pipe()
        producer.standardError = producerStderr
        consumer.standardOutput = consumerStdout
        consumer.standardError = consumerStderr

        let producerInput = producerInvocation.standardInput.map { _ in Pipe() }
        if let producerInput {
            producer.standardInput = producerInput
        }

        do {
            try consumer.run()
            try producer.run()
        } catch {
            if producer.isRunning {
                producer.terminate()
                producer.waitUntilExit()
            }
            if consumer.isRunning {
                consumer.terminate()
                consumer.waitUntilExit()
            }
            try? archivePipe.fileHandleForReading.close()
            try? archivePipe.fileHandleForWriting.close()
            try? producerStderr.fileHandleForReading.close()
            try? consumerStdout.fileHandleForReading.close()
            try? consumerStderr.fileHandleForReading.close()
            throw error
        }

        let producerStderrCapture = ProcessOutputCapture()
        let consumerStdoutCapture = ProcessOutputCapture()
        let consumerStderrCapture = ProcessOutputCapture()
        let outputGroup = DispatchGroup()

        capture(producerStderr.fileHandleForReading, into: producerStderrCapture, group: outputGroup)
        capture(consumerStdout.fileHandleForReading, into: consumerStdoutCapture, group: outputGroup)
        capture(consumerStderr.fileHandleForReading, into: consumerStderrCapture, group: outputGroup)

        try? archivePipe.fileHandleForReading.close()
        try? archivePipe.fileHandleForWriting.close()

        if let standardInput = producerInvocation.standardInput, let producerInput {
            if let data = standardInput.data(using: .utf8) {
                producerInput.fileHandleForWriting.write(data)
            }
            producerInput.fileHandleForWriting.closeFile()
        }

        producer.waitUntilExit()
        consumer.waitUntilExit()
        outputGroup.wait()

        let producerStderrText = String(data: producerStderrCapture.data, encoding: .utf8) ?? ""
        let consumerStderrText = String(data: consumerStderrCapture.data, encoding: .utf8) ?? ""
        let stderr = [producerStderrText, consumerStderrText]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let stdout = String(data: consumerStdoutCapture.data, encoding: .utf8) ?? ""

        if producer.terminationStatus != 0 {
            return CommandResult(exitCode: producer.terminationStatus, stdout: stdout, stderr: stderr)
        }

        return CommandResult(exitCode: consumer.terminationStatus, stdout: stdout, stderr: stderr)
    }

    private func capture(_ handle: FileHandle, into capture: ProcessOutputCapture, group: DispatchGroup) {
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            capture.data = handle.readDataToEndOfFile()
            group.leave()
        }
    }

    private func applyEnvironment(to process: Process) {
        guard let environment else { return }
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in override }
    }
}

private final class ProcessOutputCapture: @unchecked Sendable {
    var data = Data()
}

private final class StreamingStderrState: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingLine = ""
    private(set) var data = Data()

    func append(data: Data, text: String) -> [Substring] {
        lock.lock()
        defer { lock.unlock() }
        self.data.append(data)
        pendingLine += text
        let lines = pendingLine.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
        pendingLine = lines.last.map(String.init) ?? ""
        return Array(lines.dropLast())
    }

    func appendRemainder(_ data: Data) -> String {
        lock.lock()
        defer { lock.unlock() }
        self.data.append(data)
        pendingLine += String(data: data, encoding: .utf8) ?? ""
        let finalLine = pendingLine
        pendingLine = ""
        return finalLine
    }
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
