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

                if entries.isEmpty {
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
    }

    private func loadHistory() {
        do {
            entries = try store.load()
            if selectedID == nil || !entries.contains(where: { $0.id == selectedID }) {
                selectedID = entries.first?.id
            }
            statusMessage = nil
        } catch {
            entries = []
            selectedID = nil
            statusMessage = "Could not read upload history."
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
                Spacer()
                Text(entry.createdAt, style: .time)
                    .foregroundStyle(.secondary)
            }

            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.targetName)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(entry.createdAt, format: .dateTime.year().month().day().hour().minute().second())
                        .foregroundStyle(.secondary)
                }
                Spacer()
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
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(24)
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
