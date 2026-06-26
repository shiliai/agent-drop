import Foundation

public protocol Clock {
    var now: Date { get }
}

public struct SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
}

public struct FixedClock: Clock {
    public let date: Date
    public init(date: Date) {
        self.date = date
    }
    public var now: Date { date }
}

public struct RemoteInboxPath {
    private let clock: Clock
    private let calendar: Calendar

    public init(clock: Clock = SystemClock(), calendar: Calendar = .gregorianUTC) {
        self.clock = clock
        self.calendar = calendar
    }

    public var dateFolder: String {
        let components = calendar.dateComponents([.year, .month, .day], from: clock.now)
        return String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
    }

    public var relativeDirectory: String {
        ".agent-inbox/\(dateFolder)"
    }

    public var displayDirectory: String {
        "~/" + relativeDirectory + "/"
    }

    public func displayPath(forRemoteName remoteName: String) -> String {
        displayDirectory + remoteName
    }
}

extension Calendar {
    @usableFromInline
    static var gregorianUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
