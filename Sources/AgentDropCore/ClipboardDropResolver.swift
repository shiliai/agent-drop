import Foundation

public struct ClipboardDropSnapshot: Equatable, Sendable {
    public let fileURLs: [URL]
    public let hasImageData: Bool
    public let text: String?

    public init(fileURLs: [URL] = [], hasImageData: Bool = false, text: String? = nil) {
        self.fileURLs = fileURLs
        self.hasImageData = hasImageData
        self.text = text
    }
}

public struct ClipboardImageDrop: Equatable, Sendable {
    public let remoteName: String
    public let localDisplayName: String

    public init(remoteName: String, localDisplayName: String) {
        self.remoteName = remoteName
        self.localDisplayName = localDisplayName
    }
}

public enum ClipboardDropKind: Equatable, Sendable {
    case files
    case image(ClipboardImageDrop)
}

public struct ClipboardDropReadyItem: Equatable, Sendable {
    public let kind: ClipboardDropKind
    public let sources: [UploadSourceFile]
    public let summary: String

    public init(kind: ClipboardDropKind, sources: [UploadSourceFile], summary: String) {
        self.kind = kind
        self.sources = sources
        self.summary = summary
    }
}

public enum ClipboardDropInvalidReason: Equatable, Sendable {
    case unsupportedLocalItems([String])

    public var message: String {
        switch self {
        case let .unsupportedLocalItems(items):
            let joined = items.joined(separator: ", ")
            return "Clipboard contains local items that cannot be dropped: \(joined)"
        }
    }
}

public enum ClipboardDropResolution: Equatable, Sendable {
    case empty
    case invalid(ClipboardDropInvalidReason)
    case ready(ClipboardDropReadyItem)
}

public enum ClipboardDropResolver {
    public static func resolve(
        _ snapshot: ClipboardDropSnapshot,
        date: Date = Date(),
        timeZone: TimeZone = .current,
        fileManager: FileManager = .default
    ) -> ClipboardDropResolution {
        if !snapshot.fileURLs.isEmpty {
            return resolveFileURLs(snapshot.fileURLs, fileManager: fileManager)
        }

        if snapshot.hasImageData {
            let name = screenshotName(date: date, timeZone: timeZone)
            return .ready(ClipboardDropReadyItem(
                kind: .image(ClipboardImageDrop(remoteName: name, localDisplayName: name)),
                sources: [],
                summary: "Clipboard item ready"
            ))
        }

        return .empty
    }

    public static func screenshotName(date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot \(formatter.string(from: date)).png"
    }

    private static func resolveFileURLs(
        _ urls: [URL],
        fileManager: FileManager
    ) -> ClipboardDropResolution {
        let selection = FileSelection.validate(urls, fileManager: fileManager)

        guard selection.rejected.isEmpty else {
            return .invalid(.unsupportedLocalItems(selection.rejected.map { rejected in
                "\(rejected.url.lastPathComponent): \(rejected.reason.clipboardDescription)"
            }))
        }

        let sources = selection.files.map { url in
            UploadSourceFile(
                sourceURL: url,
                remoteName: url.lastPathComponent,
                localDisplayName: url.lastPathComponent,
                isDirectory: isDirectory(url, fileManager: fileManager)
            )
        }

        return .ready(ClipboardDropReadyItem(
            kind: .files,
            sources: sources,
            summary: summary(for: sources)
        ))
    }

    private static func summary(for sources: [UploadSourceFile]) -> String {
        if sources.count == 1, let source = sources.first {
            return "\(source.localDisplayName) ready"
        }

        return "\(sources.count) local items ready"
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

private extension RejectionReason {
    var clipboardDescription: String {
        switch self {
        case .missing:
            return "missing"
        case .notRegularFile:
            return "not a regular file"
        }
    }
}
