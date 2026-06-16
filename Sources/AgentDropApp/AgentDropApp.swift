import SwiftUI
import AppKit
import AgentDropCore

@main
struct AgentDropApp: App {
    var body: some Scene {
        WindowGroup {
            UploadHistoryView()
        }
    }
}

private struct UploadHistoryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var entries: [UploadHistoryEntry] = []
    @State private var selectedID: UploadHistoryEntry.ID?
    @State private var loadErrorMessage: String?
    @State private var statusMessage: String?

    private let store = UploadHistoryStore()

    var selectedEntry: UploadHistoryEntry? {
        entries.first { $0.id == selectedID } ?? entries.first
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recent Uploads")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    Button("Refresh") {
                        loadHistory()
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
                        "No uploads yet",
                        systemImage: "tray",
                        description: Text("Right-click a file in Finder, choose Agent Drop, then select an SSH target.")
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
                    "Select an upload",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Upload details and copyable remote paths will appear here.")
                )
            }
        }
        .frame(minWidth: 760, minHeight: 420)
        .onAppear(perform: loadHistory)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                loadHistory()
            }
        }
        .onChange(of: selectedID) { _, _ in
            statusMessage = nil
        }
    }

    private func loadHistory() {
        do {
            entries = try store.load()
            loadErrorMessage = nil
            if selectedID == nil || !entries.contains(where: { $0.id == selectedID }) {
                selectedID = entries.first?.id
            }
            statusMessage = nil
        } catch {
            entries = []
            selectedID = nil
            loadErrorMessage = "Could not read upload history."
            statusMessage = nil
        }
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
            return "\(entry.localFileNames.count) \(noun) uploaded"
        }
        return entry.errorMessage ?? "Upload failed"
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
                    Text("Local Files")
                        .font(.headline)
                    ForEach(entry.localFileNames, id: \.self) { name in
                        Text(name)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(name)
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
            statusMessage = "Copied remote paths."
        } else {
            statusMessage = "Could not copy remote paths."
        }
    }
}
