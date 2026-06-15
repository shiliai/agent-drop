import Cocoa
import FinderSync
import AgentDropCore

final class FinderSync: FIFinderSync {
    private let runner = ProcessCommandRunner()

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: NSHomeDirectory())]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let menu = NSMenu(title: "Agent Drop")
        let root = NSMenuItem(title: "Agent Drop", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Agent Drop")

        let targets = discoverTargets()
        if targets.isEmpty {
            let empty = NSMenuItem(title: "No SSH targets found", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for target in targets {
                let suffix = target.source == .active ? "active" : "config"
                let item = NSMenuItem(title: "\(target.name)    \(suffix)", action: #selector(sendToTarget(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = target.connectName
                submenu.addItem(item)
            }
        }

        root.submenu = submenu
        menu.addItem(root)
        return menu
    }

    @objc private func sendToTarget(_ sender: NSMenuItem) {
        guard let connectName = sender.representedObject as? String else { return }
        let urls = FIFinderSyncController.default().selectedItemURLs() ?? []

        DispatchQueue.global(qos: .userInitiated).async {
            let selection = FileSelection.validate(urls)
            if let failureMessage = Self.selectionFailureMessage(urls: urls, selection: selection) {
                Self.notify(title: "Agent Drop failed", body: failureMessage)
                return
            }

            let target = SSHTarget(name: connectName, connectName: connectName, source: .config)
            do {
                let uploaded = try UploadService(runner: ProcessCommandRunner()).upload(files: selection.files, target: target)
                Self.notify(title: "Agent Drop", body: "Uploaded \(uploaded.count) file(s) to \(target.name). Copied remote path(s).")
            } catch {
                Self.notify(title: "Agent Drop failed", body: String(describing: error))
            }
        }
    }

    private func discoverTargets() -> [SSHTarget] {
        let configPath = NSString(string: "~/.ssh/config").expandingTildeInPath
        let configText = (try? String(contentsOfFile: configPath)) ?? ""
        let configured = SSHConfigParser().parse(configText)
        let ps = (try? runner.run(CommandInvocation(executable: "/bin/ps", arguments: ["-axo", "command"])))?.stdout ?? ""
        let active = ActiveSSHParser().parseProcessCommands(ps.split(separator: "\n").map(String.init))
        return TargetResolver.merge(active: active, configured: configured)
    }

    private static func selectionFailureMessage(urls: [URL], selection: FileSelectionResult) -> String? {
        if urls.isEmpty {
            return "No files selected."
        }

        let messages = FileSelection.cliFailureMessages(for: selection)
        guard !messages.isEmpty else { return nil }
        return messages.joined(separator: "\n")
    }

    private static func notify(title: String, body: String) {
        DispatchQueue.main.async {
            let notification = NSUserNotification()
            notification.title = title
            notification.informativeText = body
            NSUserNotificationCenter.default.deliver(notification)
        }
    }
}
