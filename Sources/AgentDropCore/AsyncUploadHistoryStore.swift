public struct AsyncUploadHistoryStore: Sendable {
    private let store: UploadHistoryStore

    public init(store: UploadHistoryStore = UploadHistoryStore()) {
        self.store = store
    }

    public func load() async throws -> [UploadHistoryEntry] {
        try await Task.detached(priority: .utility) {
            try store.load()
        }.value
    }

    public func append(_ entry: UploadHistoryEntry) async throws {
        try await Task.detached(priority: .utility) {
            try store.append(entry)
        }.value
    }
}
