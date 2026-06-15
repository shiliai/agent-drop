import SwiftUI

@main
struct AgentDropApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 16) {
                Text("Agent Drop")
                    .font(.title)
                Text("Right-click files in Finder, choose Agent Drop, then choose an SSH target.")
                    .foregroundStyle(.secondary)
                Text("Uploaded files land in ~/.agent-inbox/YYYY-MM-DD/ on the remote machine. The final remote paths are copied to your Mac clipboard.")
                    .foregroundStyle(.secondary)
                Button("Open Extensions Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")!)
                }
            }
            .padding(24)
            .frame(width: 560, height: 260)
        }
    }
}
