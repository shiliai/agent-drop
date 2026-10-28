import SwiftUI
import AppKit
import AgentDropCore

struct TransferActivityView: View {
    let entries: [UploadHistoryEntry]
    let queue: TransferQueue
    let loadErrorMessage: String?
    let onRefresh: () -> Void
    @State private var filter = ActivityFilter.all

    private enum ActivityFilter: String, CaseIterable {
        case all = "All"
        case active = "Active"
        case failed = "Failed"
        case cancelled = "Cancelled"
        case completed = "Completed"
    }

    private var filteredEntries: [UploadHistoryEntry] {
        TransferActivityOrdering.ordered(entries.filter {
            switch filter {
            case .all: return true
            case .active: return $0.status == .running
            case .failed: return $0.status == .failed
            case .cancelled: return $0.status == .cancelled
            case .completed: return $0.status == .succeeded
            }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Activity")
                    .font(.headline)
                Text("\(filteredEntries.count) \(filter == .all ? "total" : filter.rawValue.lowercased())")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Transfers", selection: $filter) {
                    ForEach(ActivityFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 285)
                Button(action: onRefresh) { Image(systemName: "arrow.clockwise") }
                    .help("Refresh transfers")
                    .accessibilityLabel("Refresh transfers")
            }

            if let message = queue.persistenceError ?? loadErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }

            if filteredEntries.isEmpty {
                ContentUnavailableView("No \(filter == .all ? "Transfers" : filter.rawValue + " Transfers")", systemImage: "arrow.up.arrow.down.circle")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            if filter == .all {
                                activitySection("In Progress", items: filteredEntries.filter { $0.status == .running })
                                activitySection("Recent", items: filteredEntries.filter { $0.status != .running })
                            } else {
                                activitySection(filter == .active ? "In Progress" : filter.rawValue, items: filteredEntries)
                            }
                        } header: {
                            ActivityTableHeader()
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .textBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func activitySection(_ title: String, items: [UploadHistoryEntry]) -> some View {
        if !items.isEmpty {
            Text("\(title) (\(items.count))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
                .padding(.bottom, 2)
            ForEach(items) { entry in
                TransferActivityRow(entry: entry, queue: queue, showsMetadataColumns: true)
                Divider()
            }
        }
    }
}

struct SubmittedTransfersView: View {
    let ids: [UUID]
    let queue: TransferQueue

    var body: some View {
        VStack(spacing: 12) {
            ForEach(queue.entries.filter { ids.contains($0.id) }) { entry in
                TransferActivityRow(entry: entry, queue: queue)
                Divider()
            }
        }
    }
}

struct TransferActivityRow: View {
    let entry: UploadHistoryEntry
    let queue: TransferQueue
    var showsMetadataColumns = false
    @State private var isExpanded = false
    @State private var isHovered = false

    private var isQueued: Bool { queue.pendingIDs.contains(entry.id) }
    private var isOwnedByQueue: Bool { queue.entries.contains { $0.id == entry.id } }
    private var isUnknown: Bool {
        entry.status == .running && !queue.entries.contains { $0.id == entry.id }
            && Date().timeIntervalSince(entry.createdAt) > TransferStatusSummary.defaultRunningHistoryStaleInterval
    }

    private var status: String {
        switch entry.status {
        case .running:
            if isQueued { return "Queued" }
            if isUnknown { return "Status unknown" }
            return entry.direction == .upload ? "Uploading" : "Downloading"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        case .succeeded: return "Completed"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: ActivityTableLayout.spacing) {
                identity
                    .frame(minWidth: showsMetadataColumns ? ActivityTableLayout.minimumNameWidth : nil, maxWidth: .infinity, alignment: .leading)
                progressSummary
                if showsMetadataColumns {
                    TransferMetricCells(entry: entry)
                }
                actions
            }
            .frame(minHeight: 42)
            if !showsMetadataColumns, let error = entry.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .help(error)
            }
            if isExpanded {
                transferDetails
                    .padding(.top, 6)
                    .padding(.leading, 44)
                if !showsMetadataColumns {
                    TransferMetricsView(entry: entry)
                        .padding(.leading, 44)
                }
            }
        }
        .padding(.horizontal, showsMetadataColumns ? ActivityTableLayout.inset : 0)
        .padding(.vertical, showsMetadataColumns ? 5 : 0)
        .background(isHovered ? Color.primary.opacity(0.035) : Color.clear)
        .onHover { isHovered = $0 }
    }

    private var identity: some View {
        HStack(spacing: 8) {
            Button {
                isExpanded.toggle()
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .frame(width: 12, height: 24)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Hide transfer details" : "Show transfer details")
            .accessibilityLabel(isExpanded ? "Hide transfer details" : "Show transfer details")
            Image(systemName: entry.direction == .upload ? "arrow.up.circle" : "arrow.down.circle")
                .font(.callout)
                .foregroundStyle(entry.status == .failed ? .red : .secondary)
                .frame(width: 16, height: 20)
                .accessibilityLabel(entry.direction == .upload ? "Upload" : "Download")
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.localFileNames.isEmpty ? entry.remoteDisplayPaths.joined(separator: ", ") : entry.localFileNames.joined(separator: ", "))
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help((entry.localDisplayPaths + entry.remoteDisplayPaths).joined(separator: "\n"))
                Text(entry.targetName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(entry.targetName)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actions: some View {
        Group {
            if entry.status == .running, isOwnedByQueue {
                Button { queue.cancel(entry) } label: {
                    Image(systemName: "xmark.circle")
                }
                .help(isQueued ? "Cancel queued transfer" : "Stop transfer")
                .accessibilityLabel(isQueued ? "Cancel queued transfer" : "Stop transfer")
            } else if entry.status == .failed || entry.status == .cancelled {
                RetryTransferButton(entry: entry, queue: queue)
                    .labelStyle(.iconOnly)
            } else if let payload = entry.copyPayload {
                Button {
                    NSPasteboard.general.clearContents()
                    _ = NSPasteboard.general.setString(payload, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                    .help("Copy paths")
                    .accessibilityLabel("Copy paths")
            } else {
                Color.clear
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.borderless)
        .frame(width: ActivityTableLayout.actionWidth, height: 24)
    }

    private var transferDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Recorded", value: entry.createdAt.formatted(date: .complete, time: .standard))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error = entry.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            detailPaths("Remote Paths", paths: entry.remoteDisplayPaths)
            detailPaths("Local Paths", paths: entry.localDisplayPaths.isEmpty ? entry.localFileNames : entry.localDisplayPaths)
        }
    }

    @ViewBuilder
    private func detailPaths(_ title: String, paths: [String]) -> some View {
        if !paths.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption.weight(.semibold))
                Text(paths.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var progressSummary: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(status)
                    .foregroundStyle(entry.status == .failed ? .red : (entry.status == .cancelled ? .orange : .secondary))
                Spacer(minLength: 0)
                if entry.status == .running, !isQueued, !isUnknown {
                    Text(entry.progress?.percentText ?? "")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption2.monospacedDigit())
            if entry.status == .running, !isQueued, !isUnknown {
                if let fraction = entry.progress?.fractionCompleted {
                    ProgressView(value: fraction)
                        .controlSize(.small)
                    if let eta = entry.progress?.etaText {
                        Text("ETA \(eta)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
        }
        .lineLimit(1)
        .frame(width: ActivityTableLayout.statusWidth, height: 42, alignment: .leading)
        .help(entry.errorMessage ?? status)
    }
}

private enum ActivityTableLayout {
    static let minimumNameWidth: CGFloat = 160
    static let statusWidth: CGFloat = 110
    static let dateWidth: CGFloat = 84
    static let sizeWidth: CGFloat = 64
    static let speedWidth: CGFloat = 76
    static let actionWidth: CGFloat = 24
    static let spacing: CGFloat = 12
    static let inset: CGFloat = 8
}

private struct ActivityTableHeader: View {
    var body: some View {
        HStack(spacing: ActivityTableLayout.spacing) {
            Text("Transfer")
                .padding(.leading, 44)
                .frame(minWidth: ActivityTableLayout.minimumNameWidth, maxWidth: .infinity, alignment: .leading)
            Text("Status").frame(width: ActivityTableLayout.statusWidth, alignment: .leading)
            Text("Start").frame(width: ActivityTableLayout.dateWidth, alignment: .leading)
            Text("Finish").frame(width: ActivityTableLayout.dateWidth, alignment: .leading)
            Text("Size").frame(width: ActivityTableLayout.sizeWidth, alignment: .trailing)
            Text("Speed").frame(width: ActivityTableLayout.speedWidth, alignment: .trailing)
            Color.clear.frame(width: ActivityTableLayout.actionWidth)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, ActivityTableLayout.inset)
        .frame(height: 28)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .combine)
    }
}

private struct TransferMetricCells: View {
    let entry: UploadHistoryEntry

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: ActivityTableLayout.spacing) {
                dateCell(entry.startedAt, label: "Start")
                dateCell(entry.completedAt, label: "Finish")
                Text(entry.totalBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "--")
                    .frame(width: ActivityTableLayout.sizeWidth, alignment: .trailing)
                    .help(entry.totalBytes.map { "\($0) bytes" } ?? "Size unavailable")
                    .accessibilityLabel("Size")
                    .accessibilityValue(entry.totalBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Unavailable")
                speedCell(now: context.date)
            }
            .font(.caption.monospacedDigit())
            .lineLimit(1)
        }
    }

    private func dateCell(_ date: Date?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(date?.formatted(date: .omitted, time: .standard) ?? "--")
            if let date {
                Text(date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: ActivityTableLayout.dateWidth, alignment: .leading)
        .help(date?.formatted(date: .complete, time: .standard) ?? "\(label) unavailable")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(date?.formatted(date: .complete, time: .standard) ?? "Unavailable")
    }

    private func speedCell(now: Date) -> some View {
        let average = entry.averageBytesPerSecond(now: now).map {
            ByteCountFormatter.string(fromByteCount: Int64(min($0.rounded(), Double(Int64.max / 2))), countStyle: .file) + "/s"
        }
        let live = entry.status == .running ? entry.progress?.speedText : nil
        return VStack(alignment: .trailing, spacing: 3) {
            Text(live ?? average ?? "--")
            if let average {
                Text(live == nil ? "Average" : "Avg \(average)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: ActivityTableLayout.speedWidth, alignment: .trailing)
        .help(average.map { "Average speed: \($0)" } ?? "Average speed unavailable")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Speed")
        .accessibilityValue([live.map { "Current \($0)" }, average.map { "Average \($0)" }].compactMap { $0 }.joined(separator: ", "))
    }
}

struct TransferMetricsView: View {
    let entry: UploadHistoryEntry

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
                metric("Started", value: timestamp(entry.startedAt), help: entry.startedAt?.formatted(date: .complete, time: .standard))
                metric("Finished", value: timestamp(entry.completedAt), help: entry.completedAt?.formatted(date: .complete, time: .standard))
                metric("Size", value: entry.totalBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "--")
                metric("Average", value: entry.averageBytesPerSecond(now: context.date).map {
                    ByteCountFormatter.string(fromByteCount: Int64(min($0.rounded(), Double(Int64.max / 2))), countStyle: .file) + "/s"
                } ?? "--")
            }
            .font(.caption2.monospacedDigit())
        }
    }

    private func timestamp(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .standard) ?? "--"
    }

    private func metric(_ label: String, value: String, help: String? = nil) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value)
                .lineLimit(1)
                .help(help ?? value)
        }
    }
}

struct RetryTransferButton: View {
    let entry: UploadHistoryEntry
    let queue: TransferQueue
    @State private var selectionError: String?
    @State private var isShowingError = false

    private var needsFileSelection: Bool {
        (entry.status == .failed || entry.status == .cancelled)
            && entry.direction == .upload
            && entry.resolvedRetryRequest == nil
    }

    var body: some View {
        Button {
            if needsFileSelection { selectFilesForRetry() } else { queue.retry(entry) }
        } label: {
            Label(queue.retryingIDs.contains(entry.id) ? "Retrying" : (needsFileSelection ? "Retry..." : "Retry"), systemImage: "arrow.clockwise")
        }
        .disabled(!needsFileSelection && !queue.canRetry(entry))
        .help(needsFileSelection ? "Select the original files to retry upload to \(entry.targetName)" : "Retry using the original host and source paths")
        .alert("Could not retry transfer", isPresented: $isShowingError) {
            Button("OK", role: .cancel) {}
        } message: { Text(selectionError ?? "No supported files selected.") }
    }

    private func selectFilesForRetry() {
        let panel = NSOpenPanel()
        panel.title = "Retry upload to \(entry.targetName)"
        panel.prompt = "Upload"
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let selection = FileSelection.validate(panel.urls)
        let failures = FileSelection.cliFailureMessages(for: selection)
        guard failures.isEmpty else {
            selectionError = failures.joined(separator: "\n")
            isShowingError = true
            return
        }
        let target = SSHTarget(name: entry.targetName, source: .config)
        queue.enqueue(selection.files.map { file in
            .upload(target: target, sources: [UploadSourceFile(
                sourceURL: file, remoteName: file.lastPathComponent,
                isDirectory: (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            )])
        })
    }
}
