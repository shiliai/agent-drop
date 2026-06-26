import SwiftUI
import AppKit
import AgentDropCore

@main
struct AgentDropApp: App {
    @State private var selectedRoute: AgentDropRoute?

    var body: some Scene {
        WindowGroup {
            TransferWindowView(selectedRoute: $selectedRoute)
                .onOpenURL { url in
                    selectedRoute = AgentDropRoute(url: url)
                }
        }
    }
}

private struct TransferWindowView: View {
    @Binding var selectedRoute: AgentDropRoute?

    @State private var selectedTab = TransferTab.history
    @State private var historyRefreshToken = UUID()

    var body: some View {
        TabView(selection: $selectedTab) {
            UploadHistoryView(refreshToken: historyRefreshToken)
                .tabItem {
                    Label("History", systemImage: "clock")
                }
                .tag(TransferTab.history)

            PullFormView {
                historyRefreshToken = UUID()
            }
            .tabItem {
                Label("Pull from...", systemImage: "arrow.down.circle")
            }
            .tag(TransferTab.pull)
        }
        .frame(minWidth: 820, minHeight: 500)
        .onChange(of: selectedRoute) { _, route in
            apply(route)
        }
        .onAppear {
            apply(selectedRoute)
        }
    }

    private func apply(_ route: AgentDropRoute?) {
        switch route {
        case .pull:
            selectedTab = .pull
            selectedRoute = nil
        case nil:
            break
        }
    }
}

private enum TransferTab {
    case history
    case pull
}

private struct PullFormView: View {
    let onHistoryRecorded: () -> Void

    @State private var targets: [SSHTarget] = []
    @State private var selectedTargetID: SSHTarget.ID?
    @State private var remotePathText = ""
    @State private var status = PullStatus.idle
    @State private var isDownloading = false
    @State private var didInitialLoad = false
    @State private var activePullOperationID: UUID?

    private let historyStore = AsyncUploadHistoryStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Pull from SSH")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    loadTargets(applyClipboardPrefill: false)
                } label: {
                    Label("Refresh Targets", systemImage: "arrow.clockwise")
                }
                .disabled(isDownloading)
            }

            Form {
                Picker("SSH Target", selection: $selectedTargetID) {
                    Text("Select a target").tag(SSHTarget.ID?.none)
                    ForEach(targets) { target in
                        Text(targetLabel(for: target)).tag(SSHTarget.ID?.some(target.id))
                    }
                }
                .disabled(isDownloading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Remote Paths")
                        .font(.headline)
                    TextEditor(text: $remotePathText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor))
                        }
                        .disabled(isDownloading)
                }

                LabeledContent("Destination") {
                    Text("~/Downloads/Agent Drop/")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .formStyle(.grouped)

            statusView

            HStack {
                Spacer()
                Button {
                    startDownload()
                } label: {
                    if isDownloading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(minWidth: 120)
                .disabled(isDownloading)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            guard !didInitialLoad else { return }
            didInitialLoad = true
            loadTargets(applyClipboardPrefill: true)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .idle:
            EmptyView()
        case let .progress(message):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(message)
                    .foregroundStyle(.secondary)
            }
        case let .success(paths):
            VStack(alignment: .leading, spacing: 8) {
                Label("Downloaded and copied local paths.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(paths.joined(separator: "\n"))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        case let .failure(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    private var selectedTarget: SSHTarget? {
        guard let selectedTargetID else { return nil }
        return targets.first { $0.id == selectedTargetID }
    }

    private func loadTargets(applyClipboardPrefill: Bool) {
        let discoveredTargets = discoverTargets()
        targets = discoveredTargets

        if let selectedTargetID, !discoveredTargets.contains(where: { $0.id == selectedTargetID }) {
            self.selectedTargetID = nil
        }

        if applyClipboardPrefill {
            prefillFromClipboard(targets: discoveredTargets)
        }
    }

    private func prefillFromClipboard(targets: [SSHTarget]) {
        let clipboardText = NSPasteboard.general.string(forType: .string)
        guard let prefill = PullFormPrefill.evaluate(clipboardText: clipboardText, targets: targets) else {
            return
        }

        remotePathText = prefill.pathText
        if let selectedTargetID = prefill.selectedTargetID {
            self.selectedTargetID = selectedTargetID
        }
    }

    private func startDownload() {
        guard !isDownloading else { return }
        let operationID = UUID()
        activePullOperationID = operationID
        status = .idle

        guard let target = selectedTarget else {
            status = .failure("Select an SSH target before downloading.")
            return
        }

        let rawRemotePaths = normalizedInputLines(from: remotePathText)
        guard !rawRemotePaths.isEmpty else {
            status = .failure("Enter at least one remote path.")
            return
        }

        let remotePaths: [RemotePath]
        do {
            remotePaths = try RemotePathParser.parse(remotePathText)
        } catch {
            let message = CLIErrorFormatter.message(for: error)
            status = .failure(message)
            recordFailedDownload(
                target: target,
                remotePaths: rawRemotePaths,
                message: message,
                operationID: operationID
            )
            return
        }

        isDownloading = true
        status = .progress("Downloading...")

        Task {
            let result = await runDownload(remotePaths: remotePaths, target: target)

            await MainActor.run {
                switch result {
                case let .success(downloaded):
                    status = .progress("Recording transfer...")
                    recordSucceededDownload(target: target, downloaded: downloaded, operationID: operationID) {
                        isDownloading = false
                        status = .success(downloaded.map(\.localDisplayPath))
                    }
                case let .failure(error):
                    let message = CLIErrorFormatter.message(for: error)
                    isDownloading = false
                    status = .failure(message)
                    recordFailedDownload(
                        target: target,
                        remotePaths: remotePaths.map(\.path),
                        message: message,
                        operationID: operationID
                    )
                }
            }
        }
    }

    private func runDownload(remotePaths: [RemotePath], target: SSHTarget) async -> Result<[DownloadedFile], Error> {
        await Task.detached(priority: .userInitiated) {
            do {
                let downloaded = try DownloadService().download(remotePaths: remotePaths, target: target)
                return .success(downloaded)
            } catch {
                return .failure(error)
            }
        }.value
    }

    private func recordSucceededDownload(
        target: SSHTarget,
        downloaded: [DownloadedFile],
        operationID: UUID,
        onRecorded: @escaping () -> Void
    ) {
        let entry = UploadHistoryEntry.downloadSucceeded(targetName: target.name, downloadedFiles: downloaded)
        recordHistory(entry, operationID: operationID, onRecorded: onRecorded)
    }

    private func recordFailedDownload(
        target: SSHTarget,
        remotePaths: [String],
        message: String,
        operationID: UUID,
        onRecorded: (() -> Void)? = nil
    ) {
        let entry = UploadHistoryEntry.downloadFailed(
            targetName: target.name,
            remotePaths: remotePaths,
            errorDescription: message
        )
        recordHistory(
            entry,
            operationID: operationID,
            onRecorded: onRecorded,
            onRecordFailed: { historyErrorMessage in
                status = .failure("\(message)\nCould not record transfer history: \(historyErrorMessage)")
            }
        )
    }

    private func recordHistory(
        _ entry: UploadHistoryEntry,
        operationID: UUID,
        onRecorded: (() -> Void)?,
        onRecordFailed: ((String) -> Void)? = nil
    ) {
        Task {
            do {
                try await historyStore.append(entry)
                await MainActor.run {
                    guard activePullOperationID == operationID else { return }
                    onHistoryRecorded()
                    onRecorded?()
                }
            } catch {
                let message = CLIErrorFormatter.message(for: error)
                await MainActor.run {
                    guard activePullOperationID == operationID else { return }
                    isDownloading = false
                    if let onRecordFailed {
                        onRecordFailed(message)
                    } else {
                        status = .failure("Could not record transfer history: \(message)")
                    }
                }
            }
        }
    }

    private func discoverTargets() -> [SSHTarget] {
        let runner = ProcessCommandRunner()
        let configText = (try? String(contentsOfFile: NSString(string: "~/.ssh/config").expandingTildeInPath)) ?? ""
        let configured = SSHConfigParser().parse(configText)

        let ps = (try? runner.run(CommandInvocation(executable: "/bin/ps", arguments: ["-axo", "command"])))?.stdout ?? ""
        let active = ActiveSSHParser().parseProcessCommands(ps.split(separator: "\n").map(String.init))

        return TargetResolver.merge(active: active, configured: configured)
    }

    private func targetLabel(for target: SSHTarget) -> String {
        if target.name == target.connectName {
            return "\(target.name) (\(target.source.rawValue))"
        }
        return "\(target.name) -> \(target.connectName) (\(target.source.rawValue))"
    }

    private func normalizedInputLines(from text: String) -> [String] {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private enum PullStatus: Equatable {
    case idle
    case progress(String)
    case success([String])
    case failure(String)
}

private struct UploadHistoryView: View {
    @Environment(\.scenePhase) private var scenePhase
    let refreshToken: UUID

    @State private var entries: [UploadHistoryEntry] = []
    @State private var selectedID: UploadHistoryEntry.ID?
    @State private var loadErrorMessage: String?
    @State private var statusMessage: String?
    @State private var historyWatcher: UploadHistoryFileWatcher?
    @State private var isAutoRefreshEnabled = false
    @State private var lastUpdatedAt: Date?
    @State private var activeHistoryLoadID: UUID?

    private let store = AsyncUploadHistoryStore()

    var selectedEntry: UploadHistoryEntry? {
        entries.first { $0.id == selectedID } ?? entries.first
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recent Transfers")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    Button {
                        loadHistory()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }

                if let loadErrorMessage, entries.isEmpty {
                    ContentUnavailableView(
                        "History unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadErrorMessage)
                    )
                } else if entries.isEmpty {
                    ContentUnavailableView(
                        "No transfers yet",
                        systemImage: "tray",
                        description: Text("Right-click a file in Finder to upload, or use Pull from... to download remote paths.")
                    )
                } else {
                    List(selection: $selectedID) {
                        ForEach(entries) { entry in
                            UploadHistoryRow(entry: entry)
                                .tag(entry.id)
                        }
                    }
                    .listStyle(.sidebar)
                }

                UploadHistoryStatusBar(
                    isAutoRefreshEnabled: isAutoRefreshEnabled,
                    lastUpdatedAt: lastUpdatedAt,
                    versionDisplay: AgentDropVersion.display
                )
            }
            .padding()
            .frame(minWidth: 300)
        } detail: {
            if let selectedEntry {
                UploadHistoryDetail(entry: selectedEntry, statusMessage: $statusMessage)
            } else if let loadErrorMessage {
                ContentUnavailableView(
                    "History unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadErrorMessage)
                )
            } else {
                ContentUnavailableView(
                    "Select a transfer",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Transfer details and copyable paths will appear here.")
                )
            }
        }
        .onAppear {
            loadHistory()
            startHistoryWatcher()
        }
        .onDisappear {
            stopHistoryWatcher()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                loadHistory()
                startHistoryWatcher()
            } else if phase == .background {
                stopHistoryWatcher()
            }
        }
        .onChange(of: selectedID) { _, _ in
            statusMessage = nil
        }
        .onChange(of: refreshToken) { _, _ in
            loadHistory()
        }
    }

    private func loadHistory() {
        let loadID = UUID()
        activeHistoryLoadID = loadID

        Task {
            let result: Result<[UploadHistoryEntry], Error>
            do {
                result = .success(try await store.load())
            } catch {
                result = .failure(error)
            }

            await MainActor.run {
                guard activeHistoryLoadID == loadID else { return }

                switch result {
                case let .success(loadedEntries):
                    entries = loadedEntries
                    lastUpdatedAt = Date()
                    loadErrorMessage = nil
                    if selectedID == nil || !loadedEntries.contains(where: { $0.id == selectedID }) {
                        selectedID = loadedEntries.first?.id
                    }
                    statusMessage = nil
                case .failure:
                    entries = []
                    selectedID = nil
                    loadErrorMessage = "Could not read transfer history."
                    statusMessage = nil
                }
            }
        }
    }

    private func startHistoryWatcher() {
        guard historyWatcher == nil else { return }
        let watcher = UploadHistoryFileWatcher {
            Task { @MainActor in
                loadHistory()
            }
        }
        historyWatcher = watcher
        isAutoRefreshEnabled = watcher.start()
    }

    private func stopHistoryWatcher() {
        historyWatcher?.stop()
        historyWatcher = nil
        isAutoRefreshEnabled = false
    }
}

private struct UploadHistoryStatusBar: View {
    let isAutoRefreshEnabled: Bool
    let lastUpdatedAt: Date?
    let versionDisplay: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isAutoRefreshEnabled ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
                .help(isAutoRefreshEnabled ? "Auto-refresh on" : "Auto-refresh unavailable")
                .accessibilityLabel(isAutoRefreshEnabled ? "Auto-refresh on" : "Auto-refresh unavailable")

            Text(lastUpdatedText)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)

            Spacer(minLength: 8)

            Text(versionDisplay)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    private var lastUpdatedText: String {
        guard let lastUpdatedAt else {
            return "Last updated: never"
        }

        return "Last updated: \(lastUpdatedAt.formatted(date: .omitted, time: .standard))"
    }
}

private struct UploadHistoryRow: View {
    let entry: UploadHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(entry.status == .succeeded ? "Succeeded" : "Failed", systemImage: entry.status == .succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(entry.status == .succeeded ? .green : .red)
                    .labelStyle(.iconOnly)
                Text(entry.targetName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                Spacer()
                Text(entry.createdAt, style: .time)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
        .help(entry.targetName)
    }

    private var summary: String {
        let noun = entry.localFileNames.count == 1 ? "file" : "files"
        if entry.status == .succeeded {
            return "\(entry.localFileNames.count) \(noun) \(entry.direction == .download ? "downloaded" : "uploaded")"
        }
        return entry.errorMessage ?? "\(entry.direction == .download ? "Download" : "Upload") failed"
    }
}

private struct UploadHistoryDetail: View {
    let entry: UploadHistoryEntry
    @Binding var statusMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.targetName)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Text(entry.createdAt, format: .dateTime.year().month().day().hour().minute().second())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let payload = entry.copyPayload {
                        Button("Copy Paths") {
                            copy(payload)
                        }
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                    }
                }

                LabeledContent("Status") {
                    Text(entry.status == .succeeded ? "Succeeded" : "Failed")
                        .foregroundStyle(entry.status == .succeeded ? .green : .red)
                }

                if !entry.remoteDisplayPaths.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Remote Paths")
                            .font(.headline)
                        Text(entry.remoteDisplayPaths.joined(separator: "\n"))
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }

                if let errorMessage = entry.errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Error")
                            .font(.headline)
                        Text(errorMessage)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.direction == .download ? "Local Paths" : "Local Files")
                        .font(.headline)
                    ForEach(Array(localDisplayValues.enumerated()), id: \.offset) { _, value in
                        Text(value)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(value)
                    }
                }

                if let statusMessage {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }

    private func copy(_ payload: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(payload, forType: .string) {
            statusMessage = entry.direction == .download ? "Copied local paths." : "Copied remote paths."
        } else {
            statusMessage = "Could not copy paths."
        }
    }

    private var localDisplayValues: [String] {
        if entry.direction == .download, !entry.localDisplayPaths.isEmpty {
            return entry.localDisplayPaths
        }
        return entry.localFileNames
    }
}
