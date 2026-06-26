import Foundation
import Darwin

public final class UploadHistoryFileWatcher: @unchecked Sendable {
    private let historyFileURL: URL
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "ai.shili.AgentDrop.UploadHistoryFileWatcher")
    private var source: DispatchSourceFileSystemObject?

    public init(historyFileURL: URL = UploadHistoryStore.defaultHistoryFileURL(), onChange: @escaping () -> Void) {
        self.historyFileURL = historyFileURL
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    @discardableResult
    public func start() -> Bool {
        stop()

        let directoryURL = historyFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileDescriptor = open(directoryURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            return false
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: queue
        )
        source.setEventHandler { [onChange] in
            onChange()
        }
        source.setCancelHandler {
            close(fileDescriptor)
        }
        self.source = source
        source.resume()
        return true
    }

    public func stop() {
        if let source {
            source.cancel()
            self.source = nil
        }
    }
}
