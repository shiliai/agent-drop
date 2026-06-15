import SwiftUI

@main
struct AgentDropApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text("Agent Drop")
                    .font(.title)
                Text("Finder extension and CLI helper for sending files to remote SSH agent inboxes.")
                    .foregroundStyle(.secondary)
                Text("Enable the Finder extension in System Settings if it is not visible in Finder.")
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(width: 520, height: 220)
        }
    }
}
