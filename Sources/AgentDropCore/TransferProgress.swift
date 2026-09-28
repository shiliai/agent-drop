import Foundation

public typealias TransferProgressHandler = @Sendable (TransferProgress) -> Void

public struct TransferProgress: Equatable, Sendable {
    public let completedBytes: Int64
    public let fractionCompleted: Double?
    public let bytesPerSecond: Double?
    public let estimatedTimeRemaining: TimeInterval?

    public init(
        completedBytes: Int64,
        fractionCompleted: Double?,
        bytesPerSecond: Double?,
        estimatedTimeRemaining: TimeInterval?
    ) {
        self.completedBytes = completedBytes
        self.fractionCompleted = fractionCompleted
        self.bytesPerSecond = bytesPerSecond
        self.estimatedTimeRemaining = estimatedTimeRemaining
    }

    public var percentText: String? {
        guard let fractionCompleted else { return nil }
        return "\(Int((fractionCompleted * 100).rounded()))%"
    }

    public var speedText: String? {
        guard let bytesPerSecond, bytesPerSecond > 0 else { return nil }
        return "\(Self.formatBytes(bytesPerSecond))/s"
    }

    public var etaText: String? {
        guard let estimatedTimeRemaining, estimatedTimeRemaining.isFinite else { return nil }
        let totalSeconds = max(0, Int(estimatedTimeRemaining.rounded()))
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
            .map { min(max($0 / 100, 0), 1) }
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
        return number * multiplier
    }

    private static func parseDuration(_ value: String) -> TimeInterval? {
        let components = value.split(separator: ":")
        guard components.count == 3,
              let hours = Double(components[0]),
              let minutes = Double(components[1]),
              let seconds = Double(components[2]) else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }
}
