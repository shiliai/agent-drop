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
        .updatingProgress(CommandLine.arguments.contains("--recovery")
            ? RsyncProgressParser.parse("0 nan% 00:00:00 (xfer#1, to-check=0/1)") : nil)
    private static let directoryDownload = TransferRequest.download(
        target: SSHTarget(name: "test-host", source: .config),
        paths: [RemotePath(hostHint: nil, path: "/home/test/Downloads")]
    ).entry(id: UUID(), createdAt: Date(), status: .running)
        .updatingProgress(TransferProgress(completedBytes: 820, fractionCompleted: 0.82,
            bytesPerSecond: 100, estimatedTimeRemaining: 6, totalFiles: 42,
            completedFiles: 12, currentFile: "reports/current-report.pdf"))
    @State private var entries = [CommandLine.arguments.contains("--directory-progress") ? directoryDownload : running] + (1...99).map { index in
        UploadHistoryEntry.succeeded(targetName: "test-host", uploadedFiles: [UploadedFile(localURL: URL(fileURLWithPath: "/tmp/older-\(index).txt"), remoteDisplayPath: "~/.agent-inbox/older-\(index).txt")], createdAt: Date().addingTimeInterval(Double(-index)))
    }
    @State private var queue = makeQueue()

    private static func makeQueue() -> TransferQueue {
        let store = AsyncUploadHistoryStore(store: UploadHistoryStore(historyFileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("history.json")))
        guard CommandLine.arguments.contains("--recovery") else { return TransferQueue(store: store) }
        // Isolated UI recovery fixture: no SSH, network, or user history access.
        return TransferQueue(store: store, execute: { request, _ in
            .uploaded([UploadedFile(localURL: URL(fileURLWithPath: "/tmp/activity-demo.txt"), remoteDisplayPath: "~/.agent-inbox/activity-demo.txt")])
        }, copyPaths: { _ in true })
    }
    var body: some View {
        VStack {
            Button("Complete transfer") {
                entries[0] = .succeeded(targetName: "test-host", uploadedFiles: [UploadedFile(localURL: URL(fileURLWithPath: "/tmp/activity-demo.txt"), remoteDisplayPath: "~/.agent-inbox/activity-demo.txt")], createdAt: Self.running.createdAt, id: Self.running.id)
                    .withMetrics(startedAt: Self.running.startedAt, completedAt: Date(), totalBytes: 100, transferredBytes: 100)
            }
            TransferActivityView(entries: queue.mergedEntries(with: entries), queue: queue, loadErrorMessage: nil, onRefresh: {})
        }
    }
}
