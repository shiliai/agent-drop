import Foundation

public typealias TransferProgressHandler = @Sendable (TransferProgress) -> Void

public struct TransferProgress: Codable, Equatable, Sendable {
    public let completedBytes: Int64
    public let fractionCompleted: Double?
    public let bytesPerSecond: Double?
    public let estimatedTimeRemaining: TimeInterval?
    public let totalFiles: Int?
    public let completedFiles: Int?
    public let currentFile: String?

    public init(
        completedBytes: Int64,
        fractionCompleted: Double?,
        bytesPerSecond: Double?,
        estimatedTimeRemaining: TimeInterval?,
        totalFiles: Int? = nil,
        completedFiles: Int? = nil,
        currentFile: String? = nil
    ) {
        self.completedBytes = completedBytes
        self.fractionCompleted = fractionCompleted
        self.bytesPerSecond = bytesPerSecond
        self.estimatedTimeRemaining = estimatedTimeRemaining
        self.totalFiles = totalFiles
        self.completedFiles = completedFiles
        self.currentFile = currentFile
    }

    public var fileCountText: String? {
        guard let totalFiles else { return nil }
        guard let completedFiles else { return "\(totalFiles) files total" }
        return "\(completedFiles) / \(totalFiles) files"
    }

    public var percentText: String? {
        guard let fractionCompleted, fractionCompleted.isFinite else { return nil }
        let boundedFraction = min(max(fractionCompleted, 0), 1)
        return "\(Int((boundedFraction * 100).rounded()))%"
    }

    public var speedText: String? {
        guard let bytesPerSecond, bytesPerSecond.isFinite, bytesPerSecond > 0 else { return nil }
        return "\(Self.formatBytes(bytesPerSecond))/s"
    }

    public var etaText: String? {
        guard let estimatedTimeRemaining, estimatedTimeRemaining.isFinite else { return nil }
        guard let totalSeconds = Int(exactly: max(0, estimatedTimeRemaining.rounded())) else { return nil }
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }
        if minutes > 0 {
            return String(format: "%dm %02ds", minutes, seconds)
        }
        return "\(seconds)s"
    }

    public func displayText(prefix: String) -> String {
        var details = [String]()
        if let percentText { details.append(percentText) }
        if let speedText { details.append(speedText) }
        if let etaText { details.append("ETA \(etaText)") }
        return details.isEmpty ? prefix : "\(prefix) - \(details.joined(separator: " | "))"
    }

    private static func formatBytes(_ bytes: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = max(0, bytes)
        var unitIndex = 0
        while value >= 1000, unitIndex < units.count - 1 {
            value /= 1000
            unitIndex += 1
        }

        if value >= 100 || value.rounded() == value {
            return String(format: "%.0f %@", value, units[unitIndex])
        }
        return String(format: "%.1f %@", value, units[unitIndex])
    }
}

public enum RsyncProgressParser {
    public static func parse(_ line: String) -> TransferProgress? {
        let fields = line.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        guard fields.count >= 2,
              let completedBytes = Int64(fields[0].replacingOccurrences(of: ",", with: "")) else {
            return nil
        }

        let percent = fields.first(where: { $0.hasSuffix("%") })
            .flatMap { Double($0.dropLast()) }
            // macOS rsync reports nan% for empty files. Treat it as unknown progress.
            .flatMap { $0.isFinite ? min(max($0 / 100, 0), 1) : nil }
        let speed = fields.first(where: { $0.lowercased().hasSuffix("/s") })
            .flatMap(parseRate)
        let eta = fields.drop(while: { !$0.contains(":") })
            .first
            .flatMap(parseDuration)

        guard percent != nil || speed != nil || eta != nil else { return nil }
        return TransferProgress(
            completedBytes: completedBytes,
            fractionCompleted: percent,
            bytesPerSecond: speed,
            estimatedTimeRemaining: eta
        )
    }

    private static func parseRate(_ value: String) -> Double? {
        let normalized = value.lowercased()
        guard normalized.hasSuffix("/s") else { return nil }
        let numberAndUnit = String(normalized.dropLast(2))
        let numberStart = numberAndUnit.prefix { $0.isNumber || $0 == "." }
        guard let number = Double(numberStart) else { return nil }
        let unit = String(numberAndUnit.dropFirst(numberStart.count))
        let multiplier: Double
        switch unit {
        case "b", "": multiplier = 1
        case "k", "kb", "kib": multiplier = unit == "kib" ? 1024 : 1000
        case "m", "mb", "mib": multiplier = unit == "mib" ? 1024 * 1024 : 1000 * 1000
        case "g", "gb", "gib": multiplier = unit == "gib" ? 1024 * 1024 * 1024 : 1000 * 1000 * 1000
        default: return nil
        }
        let rate = number * multiplier
        return rate.isFinite ? rate : nil
    }

    private static func parseDuration(_ value: String) -> TimeInterval? {
        let components = value.split(separator: ":")
        guard components.count == 3,
              let hours = Double(components[0]),
              let minutes = Double(components[1]),
              let seconds = Double(components[2]) else { return nil }
        let duration = hours * 3600 + minutes * 60 + seconds
        return duration.isFinite ? duration : nil
    }
}

final class DirectoryDownloadProgress: @unchecked Sendable {
    private let lock = NSLock()
    private let totalFiles: Int
    private let initialCompleted: Int?
    private let handler: TransferProgressHandler
    private var completedTransfers = 0
    private var currentFile: String?
    private var currentFileCompleted = false

    init(totalFiles: Int, initialCompleted: Int?, handler: @escaping TransferProgressHandler) {
        self.totalFiles = totalFiles
        self.initialCompleted = initialCompleted
        self.handler = handler
    }

    func start() {
        handler(snapshot(nil))
    }

    func consume(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        if line.hasPrefix("AD:>f"), let separator = line.dropFirst(3).firstIndex(of: ":") {
            currentFile = String(line[line.index(after: separator)...])
            currentFileCompleted = false
            handler(snapshot(nil))
        } else if let progress = RsyncProgressParser.parse(line) {
            if line.contains("(xfer#"), currentFile != nil, !currentFileCompleted {
                completedTransfers += 1
                currentFileCompleted = true
            }
            handler(snapshot(progress))
        }
    }

    private func snapshot(_ progress: TransferProgress?) -> TransferProgress {
        TransferProgress(
            completedBytes: progress?.completedBytes ?? 0,
            fractionCompleted: progress?.fractionCompleted,
            bytesPerSecond: progress?.bytesPerSecond,
            estimatedTimeRemaining: progress?.estimatedTimeRemaining,
            totalFiles: totalFiles,
            completedFiles: initialCompleted.map { min(totalFiles, $0 + completedTransfers) },
            currentFile: currentFile
        )
    }
}
