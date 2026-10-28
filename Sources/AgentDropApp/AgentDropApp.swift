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
    @Environment(\.scenePhase) private var scenePhase
    @Binding var selectedRoute: AgentDropRoute?

    @State private var navigation = TransferNavigationState()
    @State private var historyWatcher: UploadHistoryFileWatcher?
    @State private var isAutoRefreshEnabled = false
    @State private var lastUpdatedAt: Date?
    @State private var transferStatusSummary = TransferStatusSummary.idle
    @State private var targets: [SSHTarget] = []
    @State private var doctorReport = Doctor().run()
    @State private var historyEntries: [UploadHistoryEntry] = []
    @State private var historyLoadErrorMessage: String?
    @State private var activeHistoryLoadID: UUID?
    @State private var activeFinderUploadID: UploadHistoryEntry.ID?
    @State private var isShowingFinderUploadStatus = false
    @State private var finderStatusStaleTimer: Timer?
    @State private var transferQueue = TransferQueue(copyPaths: { payload in
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(payload, forType: .string)
    })

    private let historyStore = AsyncUploadHistoryStore()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                appNavigation

                Divider()

                if navigation.selectedSection != .activity {
                    contextColumn
                    Divider()
                }

                Group {
                    switch navigation.selectedSection {
                    case .transfer:
                        TransferWorkspaceView(
                            navigation: $navigation,
                            targets: targets,
                            doctorReport: doctorReport,
                            transferQueue: transferQueue,
                            onHistoryRecorded: refreshHistory
                        )
                    case .activity:
                        TransferActivityView(
                            entries: allHistoryEntries,
                            queue: transferQueue,
                            loadErrorMessage: historyLoadErrorMessage,
                            onRefresh: refreshHistory
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            UploadHistoryStatusBar(
                isAutoRefreshEnabled: isAutoRefreshEnabled,
                lastUpdatedAt: lastUpdatedAt,
                transferStatusSummary: activeTransferSummary,
                activeFinderUploadEntry: activeTransferCount == 1 && transferQueue.activeCount == 0 ? activeFinderUploadEntry : nil,
                versionDisplay: AgentDropVersion.display
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(minWidth: 920, minHeight: 560)
        .onChange(of: selectedRoute) { _, route in
            apply(route)
        }
        .onChange(of: transferQueue.statusSummary) { _, summary in
            clearFinderUploadStatusOwnership()
            transferStatusSummary = summary
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshHistory()
                startHistoryWatcher()
            } else if phase == .background {
                stopHistoryWatcher()
            }
        }
        .onAppear {
            refreshHistory()
            startHistoryWatcher()
            loadTargets(applyClipboardPrefill: true)
            apply(selectedRoute)
        }
        .onDisappear {
            stopHistoryWatcher()
        }
    }

    private var appNavigation: some View {
        VStack(alignment: .leading, spacing: 4) {
            AppNavigationButton(
                title: "Transfer",
                systemImage: "arrow.left.arrow.right",
                isSelected: navigation.selectedSection == .transfer
            ) {
                navigation.selectedSection = .transfer
            }

            AppNavigationButton(
                title: "Activity\(activeTransferCount > 0 ? " (\(activeTransferCount))" : "")",
                systemImage: "arrow.up.arrow.down.circle",
                isSelected: navigation.selectedSection == .activity
            ) {
                navigation.selectedSection = .activity
            }

            Spacer()
        }
        .padding(10)
        .frame(width: 150)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var contextColumn: some View {
        HostListView(
            targets: targets,
            selectedTargetID: $navigation.selectedTargetID,
            onRefresh: { loadTargets(applyClipboardPrefill: false) }
        )
    }

    private var allHistoryEntries: [UploadHistoryEntry] {
        transferQueue.mergedEntries(with: historyEntries)
    }

    private var activeTransferCount: Int {
        allHistoryEntries.filter { $0.status == .running }.count
    }

    private var activeTransferSummary: TransferStatusSummary {
        activeTransferCount > 0 ? .progress("\(activeTransferCount) transfers active") : transferStatusSummary
    }

    private var activeFinderUploadEntry: UploadHistoryEntry? {
        guard let activeFinderUploadID else { return nil }
        return historyEntries.first { $0.id == activeFinderUploadID }
    }

    private func apply(_ route: AgentDropRoute?) {
        guard let route else { return }

        if route.requiresTargetRefresh {
            loadTargets(applyClipboardPrefill: true)
        }

        navigation.apply(route)
        selectedRoute = nil
    }

    private func refreshHistory() {
        lastUpdatedAt = Date()
        loadHistory()
    }

    private func loadTargets(applyClipboardPrefill: Bool) {
        doctorReport = Doctor().run()
        let discoveredTargets = discoverTargets()
        targets = discoveredTargets
        navigation.reconcileTargets(discoveredTargets)

        if applyClipboardPrefill {
            prefillFromClipboard(targets: discoveredTargets)
        }
    }

    private func prefillFromClipboard(targets: [SSHTarget]) {
        let clipboardText = NSPasteboard.general.string(forType: .string)
        guard let prefill = PullFormPrefill.evaluate(clipboardText: clipboardText, targets: targets) else {
            return
        }

        if let selectedTargetID = prefill.selectedTargetID {
            navigation.selectedTargetID = selectedTargetID
        }
    }

    private func loadHistory() {
        let loadID = UUID()
        activeHistoryLoadID = loadID

        Task {
            let result: Result<[UploadHistoryEntry], Error>
            do {
                result = .success(try await historyStore.load())
            } catch {
                result = .failure(error)
            }

            await MainActor.run {
                guard activeHistoryLoadID == loadID else { return }

                switch result {
                case let .success(loadedEntries):
                    historyEntries = loadedEntries
                    syncFinderUploadStatus(from: loadedEntries)
                    historyLoadErrorMessage = nil
                case .failure:
                    if isShowingFinderUploadStatus {
                        clearFinderUploadStatusOwnership()
                        transferStatusSummary = .failure("Could not read transfer history.")
                    }
                    historyEntries = []
                    historyLoadErrorMessage = "Could not read transfer history."
                }
            }
        }
    }

    private func syncFinderUploadStatus(from entries: [UploadHistoryEntry], now: Date = Date()) {
        let resolution = FinderUploadStatusResolver.resolve(
            entries: entries,
            currentStatus: transferStatusSummary,
            activeUploadID: activeFinderUploadID,
            isShowingFinderUploadStatus: isShowingFinderUploadStatus,
            now: now
        )

        activeFinderUploadID = resolution.activeUploadID
        isShowingFinderUploadStatus = resolution.isShowingFinderUploadStatus
        transferStatusSummary = resolution.transferStatusSummary

        if let staleRefreshEntry = resolution.staleRefreshEntry {
            scheduleFinderStatusStaleRefresh(for: staleRefreshEntry, now: now)
            return
        }

        invalidateFinderStatusStaleTimer()
    }

    private func scheduleFinderStatusStaleRefresh(for entry: UploadHistoryEntry, now: Date) {
        invalidateFinderStatusStaleTimer()

        let staleDate = entry.createdAt.addingTimeInterval(TransferStatusSummary.defaultRunningHistoryStaleInterval)
        let fireInterval = max(staleDate.timeIntervalSince(now), 0.1)
        finderStatusStaleTimer = Timer.scheduledTimer(withTimeInterval: fireInterval, repeats: false) { _ in
            Task { @MainActor in
                finderStatusStaleTimer = nil
                refreshHistory()
            }
        }
    }

    private func clearFinderUploadStatusOwnership() {
        activeFinderUploadID = nil
        isShowingFinderUploadStatus = false
        invalidateFinderStatusStaleTimer()
    }

    private func invalidateFinderStatusStaleTimer() {
        finderStatusStaleTimer?.invalidate()
        finderStatusStaleTimer = nil
    }

    private func startHistoryWatcher() {
        guard historyWatcher == nil else { return }
        let watcher = UploadHistoryFileWatcher {
            Task { @MainActor in
                refreshHistory()
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

private struct AppNavigationButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.accentColor.opacity(0.16))
                    }
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .fontWeight(isSelected ? .semibold : .regular)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct TransferWorkspaceView: View {
    @Binding var navigation: TransferNavigationState
    let targets: [SSHTarget]
    let doctorReport: DoctorReport
    let transferQueue: TransferQueue
    let onHistoryRecorded: () -> Void

    @State private var remotePathText = ""
    @State private var didInitialLoad = false
    @State private var clipboardRefreshID = UUID()

    var body: some View {
        WorkspaceContent(title: "Transfer", accessory: {
            HStack {
                Button {
                    if navigation.transferMode == .pull { prefillFromClipboard(targets: targets) }
                    clipboardRefreshID = UUID()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh clipboard")
                .accessibilityLabel("Refresh clipboard")
                transferModePicker
            }
        }) {
            currentTransferPane
        }
        .onAppear {
            guard !didInitialLoad else { return }
            didInitialLoad = true
            if remotePathText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                prefillFromClipboard(targets: targets)
            }
        }
        .onChange(of: navigation.transferMode) { _, mode in
            if mode == .pull, remotePathText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                prefillFromClipboard(targets: targets)
            }
        }
        .onChange(of: targets) { _, targets in
            if navigation.transferMode == .pull, remotePathText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                prefillFromClipboard(targets: targets)
            }
        }
    }

    private var selectedTarget: SSHTarget? {
        guard let selectedTargetID = navigation.selectedTargetID else { return nil }
        return targets.first { $0.id == selectedTargetID }
    }

    private var transferModePicker: some View {
        Picker("Transfer Mode", selection: $navigation.transferMode) {
            Text("Drop").tag(TransferMode.drop)
            Text("Pull from...").tag(TransferMode.pull)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 220)
    }

    @ViewBuilder
    private var currentTransferPane: some View {
        switch navigation.transferMode {
        case .drop:
            DropLandingView(
                selectedTarget: selectedTarget,
                dependencyFeedback: dependencyFeedback(for: .appDrop),
                transferQueue: transferQueue,
                clipboardRefreshID: clipboardRefreshID,
                onSwitchToPull: {
                    navigation.transferMode = .pull
                },
                onHistoryRecorded: onHistoryRecorded
            )
        case .pull:
            PullFormView(
                targets: targets,
                selectedTargetID: $navigation.selectedTargetID,
                remotePathText: $remotePathText,
                transferQueue: transferQueue,
                dependencyFeedback: dependencyFeedback(for: .appPull),
                dependencyFeedbackProvider: DependencyFeedbackProvider(),
                onHistoryRecorded: onHistoryRecorded
            )
        }
    }

    private func prefillFromClipboard(targets: [SSHTarget]) {
        let clipboardText = NSPasteboard.general.string(forType: .string)
        guard let prefill = PullFormPrefill.evaluate(clipboardText: clipboardText, targets: targets) else {
            return
        }

        remotePathText = prefill.pathText
        if let selectedTargetID = prefill.selectedTargetID {
            navigation.selectedTargetID = selectedTargetID
        }
    }

    private func dependencyFeedback(for requirement: DependencyRequirement) -> DependencyFeedback? {
        DependencyFeedback.missingFeedback(in: doctorReport, for: requirement)
    }

}

private struct WorkspaceContent<Accessory: View, Content: View>: View {
    let title: String
    let accessory: Accessory
    let content: Content

    init(
        title: String,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                accessory
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(24)
        .background(Color(nsColor: .textBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private extension WorkspaceContent where Accessory == EmptyView {
    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title: title, accessory: EmptyView.init, content: content)
    }
}

private struct HostListView: View {
    let targets: [SSHTarget]
    @Binding var selectedTargetID: SSHTarget.ID?
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Hosts")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help("Refresh targets")
                .accessibilityLabel("Refresh targets")
            }

            if targets.isEmpty {
                ContentUnavailableView(
                    "No Hosts",
                    systemImage: "network",
                    description: Text("Add SSH hosts or open an SSH session.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedTargetID) {
                    ForEach(targets) { target in
                        HostRow(target: target)
                            .tag(SSHTarget.ID?.some(target.id))
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .padding(12)
        .frame(width: 230)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct HostRow: View {
    let target: SSHTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(target.name)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .help(targetLabel(for: target))
    }

    private var subtitle: String {
        if target.name == target.connectName {
            return target.source.rawValue
        }
        return "\(target.connectName) - \(target.source.rawValue)"
    }
}

private struct DropLandingView: View {
    @Environment(\.scenePhase) private var scenePhase

    let selectedTarget: SSHTarget?
    let dependencyFeedback: DependencyFeedback?
    let transferQueue: TransferQueue
    let clipboardRefreshID: UUID
    let dependencyFeedbackProvider = DependencyFeedbackProvider()
    let onSwitchToPull: () -> Void
    let onHistoryRecorded: () -> Void

    @State private var clipboardSnapshot = AppClipboardSnapshot.empty
    @State private var clipboardResolution = ClipboardDropResolution.empty
    @State private var status = ClipboardDropStatus.idle
    @State private var isDroppingClipboard = false
    @State private var submittedIDs: [UUID] = []
    @State private var clipboardChangeCount = -1
    private let clipboardTimer = Timer.publish(every: 0.75, on: .main, in: .common).autoconnect()


    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.trailing, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            refreshClipboard(preservingStatus: true)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshClipboard(preservingStatus: true)
            }
        }
        .onChange(of: selectedTarget?.id) { _, _ in
            clearStatusWhenReady()
        }
        .onChange(of: clipboardRefreshID) { _, _ in
            refreshClipboard(preservingStatus: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshClipboard(preservingStatus: true)
        }
        .onReceive(clipboardTimer) { _ in
            guard NSApplication.shared.isActive,
                  NSPasteboard.general.changeCount != clipboardChangeCount else { return }
            refreshClipboard(preservingStatus: true)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(description)
                    .foregroundStyle(.secondary)
            }

            if let dependencyFeedback {
                Label(dependencyFeedback.message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }

            workflowCards
                .frame(maxWidth: 760, alignment: .leading)

            statusView
            SubmittedTransfersView(ids: submittedIDs, queue: transferQueue)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var finderWorkflowCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Finder workflow", systemImage: "folder")
                .font(.headline)

            Text("Select files or folders in Finder, right-click, choose Agent Drop, then pick the selected host.")
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()))
                } label: {
                    Label("Open Finder", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)

                Button(action: onSwitchToPull) {
                    Label("Pull instead", systemImage: "arrow.down.circle")
                }
            }
        }
        .padding(18)
        .frame(minWidth: 320, maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55))
        }
    }

    private var clipboardCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label("Clipboard", systemImage: "doc.on.clipboard")
                    .font(.headline)

                Spacer()

                Button {
                    startClipboardDrop()
                } label: {
                    if isDroppingClipboard {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 18, height: 18)
                    } else {
                        Label("Drop Clipboard", systemImage: "paperplane")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canDropClipboard)
                .help(dropClipboardHelp)
                .accessibilityLabel("Drop Clipboard")

                Button {
                    refreshClipboard(preservingStatus: false)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help("Refresh clipboard")
                .accessibilityLabel("Refresh clipboard")
                .disabled(isDroppingClipboard)
            }

            Label(clipboardMessage, systemImage: clipboardSystemImage)
                .foregroundStyle(clipboardForegroundStyle)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(minWidth: 320, maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55))
        }
    }

    @ViewBuilder
    private var workflowCards: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                finderWorkflowCard
                clipboardCard
            }

            VStack(alignment: .leading, spacing: 16) {
                finderWorkflowCard
                clipboardCard
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .idle:
            EmptyView()
        case let .failure(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    private var title: String {
        guard let selectedTarget else {
            return "Drop to SSH"
        }
        return "Drop to \(selectedTarget.name)"
    }

    private var description: String {
        guard let selectedTarget else {
            return "Choose a host, then use Finder or the clipboard to send files."
        }
        return "Use Finder or the clipboard to send files to \(selectedTarget.name)."
    }

    private var canDropClipboard: Bool {
        guard selectedTarget != nil, !isDroppingClipboard else { return false }
        if case .ready = clipboardResolution {
            return true
        }
        return false
    }

    private var clipboardMessage: String {
        switch clipboardResolution {
        case .empty:
            return "Copy files, folders, or an image to enable clipboard drop."
        case let .invalid(reason):
            return reason.message
        case let .ready(item):
            return item.summary
        }
    }

    private var clipboardSystemImage: String {
        switch clipboardResolution {
        case .empty:
            return "clipboard"
        case .invalid:
            return "exclamationmark.triangle"
        case let .ready(item):
            switch item.kind {
            case .files:
                return "checkmark.circle"
            case .image:
                return "photo"
            }
        }
    }

    private var clipboardForegroundStyle: Color {
        switch clipboardResolution {
        case .empty:
            return .secondary
        case .invalid:
            return .orange
        case .ready:
            return .green
        }
    }

    private var dropClipboardHelp: String {
        if selectedTarget == nil {
            return "Choose a host before dropping clipboard contents."
        }
        if isDroppingClipboard {
            return "Clipboard drop is in progress."
        }
        switch clipboardResolution {
        case .ready:
            return "Upload clipboard contents to the selected host."
        case .empty:
            return "Copy files, folders, or an image before dropping."
        case let .invalid(reason):
            return reason.message
        }
    }

    private func refreshClipboard(preservingStatus: Bool) {
        clipboardChangeCount = NSPasteboard.general.changeCount
        clipboardSnapshot = AppClipboardReader.read()
        clipboardResolution = ClipboardDropResolver.resolve(clipboardSnapshot.coreSnapshot)
        if !preservingStatus {
            status = .idle
        }
    }

    private func clearStatusWhenReady() {
        guard !isDroppingClipboard else { return }
        guard case .ready = clipboardResolution else { return }
        status = .idle
    }

    private func startClipboardDrop() {
        guard !isDroppingClipboard else { return }
        if let feedback = dependencyFeedbackProvider.feedback(for: .appDrop) {
            status = .failure(feedback.message)
            return
        }
        guard let target = selectedTarget else { return }
        refreshClipboard(preservingStatus: true)
        guard case let .ready(item) = clipboardResolution else { return }
        let snapshot = clipboardSnapshot
        isDroppingClipboard = true
        status = .idle
        Task {
            do {
                let sources: [UploadSourceFile]
                switch item.kind {
                case .files:
                    sources = item.sources
                case let .image(imageDrop):
                    guard let data = snapshot.imagePNGData else { throw ClipboardDropAppError.missingImageData }
                    let staged = try await Task.detached(priority: .userInitiated) {
                        try ClipboardImageStager.stage(pngData: data, imageDrop: imageDrop)
                    }.value
                    sources = staged.files
                }
                submittedIDs = transferQueue.enqueue(sources.map { .upload(target: target, sources: [$0]) })
                onHistoryRecorded()
            } catch {
                status = .failure(CLIErrorFormatter.message(for: error))
            }
            isDroppingClipboard = false
        }
    }

}

private struct PullFormView: View {
    let targets: [SSHTarget]
    @Binding var selectedTargetID: SSHTarget.ID?
    @Binding var remotePathText: String
    let transferQueue: TransferQueue
    let dependencyFeedback: DependencyFeedback?
    let dependencyFeedbackProvider: DependencyFeedbackProvider
    let onHistoryRecorded: () -> Void

    @State private var status = PullStatus.idle
    @State private var submittedIDs: [UUID] = []

    var body: some View {
        ScrollView { content }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pull from SSH")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(selectedTargetDescription)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Remote Paths")
                        .font(.headline)

                        Text(hostPrefixHint)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

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
                }

                Divider()

                HStack(alignment: .center) {
                    Text("Destination")
                        .font(.headline)

                    Spacer()

                    Text("~/Downloads/Agent Drop/")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Divider()

                HStack(spacing: 12) {
                    Button {
                        startDownload()
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(minWidth: 170)

                    Button {
                        openDestinationInFinder()
                    } label: {
                        Label("Open Finder", systemImage: "folder")
                    }
                    .controlSize(.large)

                    Text("Copies downloaded local paths to the clipboard.")
                        .foregroundStyle(.secondary)

                    Spacer()
                }
            }
            .padding(20)
            .frame(maxWidth: 640, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.55))
            }

            statusView
            dependencyStatusView
            SubmittedTransfersView(ids: submittedIDs, queue: transferQueue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .idle:
            EmptyView()
        case let .failure(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var dependencyStatusView: some View {
        if let dependencyFeedback {
            Label(dependencyFeedback.message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .textSelection(.enabled)
        }
    }

    private var selectedTarget: SSHTarget? {
        guard let selectedTargetID else { return nil }
        return targets.first { $0.id == selectedTargetID }
    }

    private var selectedTargetDescription: String {
        guard let selectedTarget else {
            return "Choose a host from the Hosts list before downloading."
        }
        return "Remote paths will be downloaded from \(targetLabel(for: selectedTarget))."
    }

    private var hostPrefixHint: String {
        guard let selectedTarget else {
            return "host:~/path"
        }
        return "\(selectedTarget.connectName):~/path"
    }

    private func startDownload() {
        if let feedback = dependencyFeedbackProvider.feedback(for: .appPull) {
            status = .failure(feedback.message)
            return
        }
        guard let target = selectedTarget else {
            status = .failure("Select an SSH target before downloading.")
            return
        }
        do {
            let paths = try RemotePathParser.parse(remotePathText)
            for path in paths {
                if let hint = path.hostHint, hint != target.name, hint != target.connectName {
                    throw DownloadError.hostHintMismatch(hostHint: hint, selectedTarget: target.connectName)
                }
            }
            submittedIDs = transferQueue.enqueue(paths.map { .download(target: target, paths: [$0]) })
            status = .idle
            onHistoryRecorded()
        } catch {
            status = .failure(CLIErrorFormatter.message(for: error))
        }
    }

    private func openDestinationInFinder() {
        do {
            let destinationRoot = try DownloadService.prepareDefaultDestinationRoot()
            guard NSWorkspace.shared.open(destinationRoot) else {
                status = .failure("Could not open the download folder in Finder.")
                return
            }
        } catch {
            status = .failure("Could not prepare the download folder: \(CLIErrorFormatter.message(for: error))")
        }
    }

}

private enum PullStatus: Equatable {
    case idle
    case failure(String)
}

private struct UploadHistoryStatusBar: View {
    let isAutoRefreshEnabled: Bool
    let lastUpdatedAt: Date?
    let transferStatusSummary: TransferStatusSummary
    let activeFinderUploadEntry: UploadHistoryEntry?
    let versionDisplay: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: transferStatusSummary.systemImageName)
                .foregroundStyle(statusColor)
                .imageScale(.small)
                .frame(width: 12, height: 12)
                .help(statusText)
                .accessibilityLabel(statusText)

            Text(statusText)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)

            Spacer(minLength: 8)

            Text(versionDisplay)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .help(isAutoRefreshEnabled ? "Auto-refresh on" : "Auto-refresh unavailable")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    private var statusText: String {
        if let activeFinderUploadEntry,
           let progress = activeFinderUploadEntry.progress {
            let fileCount = activeFinderUploadEntry.localFileNames.count
            let noun = fileCount == 1 ? "file" : "files"
            return progress.displayText(
                prefix: "Uploading \(fileCount) \(noun) to \(activeFinderUploadEntry.targetName)"
            )
        }
        return transferStatusSummary.statusText(lastUpdatedAt: lastUpdatedAt)
    }

    private var statusColor: Color {
        switch transferStatusSummary {
        case .idle:
            return isAutoRefreshEnabled ? .green : .orange
        case .progress:
            return .blue
        case .success:
            return .green
        case let .uploadSuccess(_, _, copiedPaths):
            return copiedPaths ? .green : .orange
        case .failure:
            return .red
        }
    }
}

private func discoverTargets() -> [SSHTarget] {
    let runner = ProcessCommandRunner()
    let configured = SSHConfigLoader().loadTargets()

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

private struct AppClipboardSnapshot: Sendable {
    let coreSnapshot: ClipboardDropSnapshot
    let imagePNGData: Data?

    static let empty = AppClipboardSnapshot(
        coreSnapshot: ClipboardDropSnapshot(),
        imagePNGData: nil
    )
}

private enum AppClipboardReader {
    static func read(_ pasteboard: NSPasteboard = .general) -> AppClipboardSnapshot {
        let fileURLs = readFileURLs(from: pasteboard)
        let imageData = fileURLs.isEmpty ? readPNGData(from: pasteboard) : nil
        let text = pasteboard.string(forType: .string)

        return AppClipboardSnapshot(
            coreSnapshot: ClipboardDropSnapshot(
                fileURLs: fileURLs,
                hasImageData: imageData != nil,
                text: text
            ),
            imagePNGData: imageData
        )
    }

    private static func readFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]

        let typedURLs = (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [NSURL])?
            .map { $0 as URL } ?? []
        let legacyFilePaths = pasteboard.propertyList(forType: .init("NSFilenamesPboardType")) as? [String] ?? []

        return ClipboardFileURLSelection.fileURLs(
            typedURLs: typedURLs,
            legacyFilePaths: legacyFilePaths
        )
    }

    private static func readPNGData(from pasteboard: NSPasteboard) -> Data? {
        if let pngData = pasteboard.data(forType: .png) {
            return pngData
        }

        guard let image = NSImage(pasteboard: pasteboard) else {
            return nil
        }
        return image.pngData()
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}

private enum ClipboardDropStatus: Equatable {
    case idle
    case failure(String)
}

private enum ClipboardDropAppError: LocalizedError {
    case missingImageData

    var errorDescription: String? {
        switch self {
        case .missingImageData:
            return "Clipboard image data is no longer available. Copy the image again and retry."
        }
    }
}
