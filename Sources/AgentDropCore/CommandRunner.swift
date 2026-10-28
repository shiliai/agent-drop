import Foundation

/// Coordinates cancellation of one or more child processes belonging to a transfer.
public final class TransferCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var processes: [ObjectIdentifier: Process] = [:]

    public init() {}

    public var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    public func cancel() {
        let processesToTerminate: [Process] = lock.withLock {
            cancelled = true
            return Array(processes.values)
        }
        for process in processesToTerminate where process.isRunning {
            process.terminate()
        }
    }

    fileprivate func register(_ process: Process) {
        let shouldTerminate = lock.withLock { () -> Bool in
            if cancelled { return true }
            processes[ObjectIdentifier(process)] = process
            return false
        }
        if shouldTerminate, process.isRunning {
            process.terminate()
        }
    }

    fileprivate func unregister(_ process: Process) {
        _ = lock.withLock { processes.removeValue(forKey: ObjectIdentifier(process)) }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

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

public protocol CancellableProgressReportingCommandRunning: ProgressReportingCommandRunning {
    func run(
        _ invocation: CommandInvocation,
        progress: (@Sendable (String) -> Void)?,
        cancellation: TransferCancellation?
    ) throws -> CommandResult
}

public protocol CommandPiping {
    func runPipeline(stdoutOf producer: CommandInvocation, intoStdinOf consumer: CommandInvocation) throws -> CommandResult
}

public protocol CancellableCommandPiping: CommandPiping {
    func runPipeline(
        stdoutOf producer: CommandInvocation,
        intoStdinOf consumer: CommandInvocation,
        cancellation: TransferCancellation?
    ) throws -> CommandResult
}

public struct ProcessCommandRunner: Sendable, CommandRunning, ProgressReportingCommandRunning, CancellableProgressReportingCommandRunning, CommandPiping, CancellableCommandPiping {
    private let environment: [String: String]?

    public init(environment: [String: String]? = nil) {
        self.environment = environment
    }

    public func run(_ invocation: CommandInvocation) throws -> CommandResult {
        try run(invocation, progress: nil, cancellation: nil)
    }

    public func run(_ invocation: CommandInvocation, cancellation: TransferCancellation?) throws -> CommandResult {
        try run(invocation, progress: nil, cancellation: cancellation)
    }

    public func run(
        _ invocation: CommandInvocation,
        progress: (@Sendable (String) -> Void)?,
        cancellation: TransferCancellation?
    ) throws -> CommandResult {
        if let progress {
            return try runWithProgress(invocation, progress: progress, cancellation: cancellation)
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

        try process.run()
        cancellation?.register(process)
        defer { cancellation?.unregister(process) }

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

        return try runWithProgress(invocation, progress: progress, cancellation: nil)
    }

    private func runWithProgress(
        _ invocation: CommandInvocation,
        progress: @escaping @Sendable (String) -> Void,
        cancellation: TransferCancellation?
    ) throws -> CommandResult {

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
        cancellation?.register(process)
        defer { cancellation?.unregister(process) }

        let stdoutCapture = ProcessOutputCapture()
        let stderrCapture = ProcessOutputCapture()
        let outputGroup = DispatchGroup()
        captureProgress(stdout.fileHandleForReading, into: stdoutCapture, group: outputGroup, progress: progress)
        captureProgress(stderr.fileHandleForReading, into: stderrCapture, group: outputGroup, progress: progress)

        if let standardInput = invocation.standardInput, let input {
            if let data = standardInput.data(using: .utf8) {
                input.fileHandleForWriting.write(data)
            }
            input.fileHandleForWriting.closeFile()
        }

        process.waitUntilExit()
        outputGroup.wait()

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutCapture.data, encoding: .utf8) ?? "",
            stderr: String(data: stderrCapture.data, encoding: .utf8) ?? ""
        )
    }

    public func runPipeline(stdoutOf producerInvocation: CommandInvocation, intoStdinOf consumerInvocation: CommandInvocation) throws -> CommandResult {
        try runPipeline(stdoutOf: producerInvocation, intoStdinOf: consumerInvocation, cancellation: nil)
    }

    public func runPipeline(
        stdoutOf producerInvocation: CommandInvocation,
        intoStdinOf consumerInvocation: CommandInvocation,
        cancellation: TransferCancellation?
    ) throws -> CommandResult {
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
            cancellation?.register(consumer)
            try producer.run()
            cancellation?.register(producer)
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

        defer {
            cancellation?.unregister(producer)
            cancellation?.unregister(consumer)
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

    private func captureProgress(
        _ handle: FileHandle,
        into capture: ProcessOutputCapture,
        group: DispatchGroup,
        progress: @escaping @Sendable (String) -> Void
    ) {
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            defer { group.leave() }
            var pendingLine = Data()
            while true {
                let data = handle.availableData
                guard !data.isEmpty else { break }
                capture.data.append(data)
                // rsync progress uses carriage returns and may arrive on either stream.
                for byte in data {
                    if byte == 10 || byte == 13 {
                        if !pendingLine.isEmpty {
                            progress(String(decoding: pendingLine, as: UTF8.self)
                                .trimmingCharacters(in: .whitespacesAndNewlines))
                            pendingLine.removeAll(keepingCapacity: true)
                        }
                    } else {
                        pendingLine.append(byte)
                    }
                }
            }
            if !pendingLine.isEmpty {
                progress(String(decoding: pendingLine, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines))
            }
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
