import SwiftUI
import AgentDropCore

@main struct ActivityRegression: App {
    var body: some Scene {
        WindowGroup("Activity Regression") { RegressionView().frame(width: 1100, height: 650) }
    }
}

@MainActor struct RegressionView: View {
    private static let running = TransferRequest.upload(
        target: SSHTarget(name: "test-host", source: .config),
        sources: [UploadSourceFile(sourceURL: URL(fileURLWithPath: "/tmp/activity-demo.txt"), remoteName: "activity-demo.txt", isDirectory: false)]
    ).entry(id: UUID(), createdAt: Date(), status: .running)
        .withMetrics(startedAt: Date(), totalBytes: 100)
    @State private var entries = [running] + (1...99).map { index in
        UploadHistoryEntry.succeeded(targetName: "test-host", uploadedFiles: [UploadedFile(localURL: URL(fileURLWithPath: "/tmp/older-\(index).txt"), remoteDisplayPath: "~/.agent-inbox/older-\(index).txt")], createdAt: Date().addingTimeInterval(Double(-index)))
    }
    @State private var queue = TransferQueue(store: AsyncUploadHistoryStore(store: UploadHistoryStore(historyFileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("history.json"))))
    var body: some View {
        VStack {
            Button("Complete transfer") {
                entries[0] = .succeeded(targetName: "test-host", uploadedFiles: [UploadedFile(localURL: URL(fileURLWithPath: "/tmp/activity-demo.txt"), remoteDisplayPath: "~/.agent-inbox/activity-demo.txt")], createdAt: Self.running.createdAt, id: Self.running.id)
                    .withMetrics(startedAt: Self.running.startedAt, completedAt: Date(), totalBytes: 100, transferredBytes: 100)
            }
            TransferActivityView(entries: entries, queue: queue, loadErrorMessage: nil, onRefresh: {})
        }
    }
}
