import Cocoa
import FinderSync
import AgentDropCore
import OSLog
import Darwin

private let logger = Logger(subsystem: "ai.shili.AgentDrop", category: "FinderSync")
private let successBadgeIdentifier = "agent-drop-success"
private let failureBadgeIdentifier = "agent-drop-failure"

final class FinderSync: FIFinderSync {
    private let runner = ProcessCommandRunner()
    private let historyStore = UploadHistoryStore()
    private let home: URL

    override init() {
        home = HostHomeDirectoryResolver.resolve(accountHomePath: Self.accountHomePath())
        super.init()
        let monitoredDirectories = FinderSyncDirectoryScope.monitoredDirectories(home: home)
        FIFinderSyncController.default().directoryURLs = Set(monitoredDirectories)
        let monitoredPaths = monitoredDirectories.map(\.path).joined(separator: ", ")
        logger.info("Registered Finder Sync directories: \(monitoredPaths, privacy: .public)")
        Self.registerBadges()
        Self.recordDiagnostic("init bundle=\(Bundle.main.bundleIdentifier ?? "unknown") directories=\(monitoredPaths)")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        logger.info("Building Finder Sync menu for kind: \(String(describing: menuKind), privacy: .public)")
        let selectedCount = FIFinderSyncController.default().selectedItemURLs()?.count ?? 0
        Self.recordDiagnostic("menu kind=\(String(describing: menuKind)) selectedCount=\(selectedCount)")
        let menu = NSMenu(title: "Agent Drop")
        let root = NSMenuItem(title: "Agent Drop", action: nil, keyEquivalent: "")
        root.image = Self.menuIcon()
        let submenu = NSMenu(title: "Agent Drop")

        let targets = discoverTargets()
        logger.info("Discovered \(targets.count, privacy: .public) SSH target(s)")
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

        if !submenu.items.isEmpty {
            submenu.addItem(.separator())
        }
        let pullItem = NSMenuItem(title: "Pull from...", action: #selector(openPullWindow(_:)), keyEquivalent: "")
        pullItem.target = self
        submenu.addItem(pullItem)

        root.submenu = submenu
        menu.addItem(root)
        return menu
    }

    @objc private func sendToTarget(_ sender: NSMenuItem) {
        let representedObject = sender.representedObject as? String
        Self.recordDiagnostic("send invoked title=\(sender.title) represented=\(representedObject ?? "nil")")
        guard let connectName = FinderMenuTargetResolver.connectName(representedObject: representedObject, title: sender.title) else {
            Self.recordDiagnostic("send rejected reason=missing target title=\(sender.title)")
            Self.notify(title: "Agent Drop failed", body: "No SSH target selected or found.")
            return
        }
        let urls = FIFinderSyncController.default().selectedItemURLs() ?? []
        Self.recordDiagnostic("send requested target=\(connectName) selected=\(urls.map(\.path).joined(separator: ", "))")

        DispatchQueue.global(qos: .userInitiated).async {
            let selection = FileSelection.validate(urls)
            if let failureMessage = Self.selectionFailureMessage(urls: urls, selection: selection) {
                Self.recordDiagnostic("send rejected target=\(connectName) reason=\(failureMessage)")
                Self.notify(title: "Agent Drop failed", body: failureMessage)
                return
            }

            let target = SSHTarget(name: connectName, connectName: connectName, source: .config)
            do {
                Self.recordDiagnostic("upload start target=\(target.connectName) files=\(selection.files.map(\.lastPathComponent).joined(separator: ", "))")
                let staged = try UploadStager.stage(files: selection.files)
                defer { try? staged.cleanup() }
                Self.recordDiagnostic("upload staged target=\(target.connectName) directory=\(staged.directory.path) files=\(staged.files.map(\.sourceURL.lastPathComponent).joined(separator: ", "))")
                let uploaded = try UploadService(runner: self.runner).upload(sources: staged.files, target: target, copyToClipboard: false)
                let entry = UploadHistoryEntry.succeeded(targetName: target.name, uploadedFiles: uploaded)
                Self.recordHistory(entry, store: self.historyStore)
                let remotePaths = uploaded.map(\.remoteDisplayPath).joined(separator: "\n")
                let copied = Self.copyToPasteboard(remotePaths)
                let body = UploadFeedbackFormatter.success(fileCount: uploaded.count, targetName: target.name, copiedPaths: copied)
                Self.recordDiagnostic("upload success target=\(target.connectName) count=\(uploaded.count) clipboard=\(copied) paths=\(remotePaths.replacingOccurrences(of: "\n", with: " | "))")
                Self.markFiles(selection.files, badgeIdentifier: successBadgeIdentifier)
                Self.notify(title: copied ? "Agent Drop" : "Agent Drop uploaded", body: body)
            } catch {
                Self.recordDiagnostic("upload failed target=\(target.connectName) error=\(String(describing: error))")
                let entry = UploadHistoryEntry.failed(
                    targetName: target.name,
                    fileURLs: selection.files,
                    errorDescription: String(describing: error)
                )
                Self.recordHistory(entry, store: self.historyStore)
                Self.markFiles(selection.files, badgeIdentifier: failureBadgeIdentifier)
                Self.notify(title: "Agent Drop failed", body: UploadFeedbackFormatter.failure(targetName: target.name, errorDescription: String(describing: error)))
            }
        }
    }

    @objc private func openPullWindow(_ sender: NSMenuItem) {
        let url = AgentDropRoute.pullURL
        Self.recordDiagnostic("pull route requested url=\(url.absoluteString)")
        if NSWorkspace.shared.open(url) {
            Self.recordDiagnostic("pull route opened")
        } else {
            let message = "Could not open Agent Drop."
            Self.recordDiagnostic("pull route failed")
            Self.notify(title: "Agent Drop failed", body: message)
        }
    }

    private func discoverTargets() -> [SSHTarget] {
        let configURL = home.appendingPathComponent(".ssh/config", isDirectory: false)
        let configText = (try? String(contentsOf: configURL)) ?? ""
        let configured = SSHConfigParser().parse(configText)
        let ps = (try? runner.run(CommandInvocation(executable: "/bin/ps", arguments: ["-axo", "command"])))?.stdout ?? ""
        let active = ActiveSSHParser().parseProcessCommands(ps.split(separator: "\n").map(String.init))
        Self.recordDiagnostic("targets configBytes=\(configText.utf8.count) configured=\(configured.count) psBytes=\(ps.utf8.count) active=\(active.count)")
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
        recordDiagnostic("notify title=\(title) body=\(body.replacingOccurrences(of: "\n", with: " | "))")
        DispatchQueue.main.async {
            let notification = NSUserNotification()
            notification.title = title
            notification.informativeText = body
            NSUserNotificationCenter.default.deliver(notification)
        }
    }

    private static func registerBadges() {
        let controller = FIFinderSyncController.default()
        controller.setBadgeImage(Self.badgeIcon(systemSymbolName: "checkmark.circle.fill", fallbackText: "✓"), label: "Agent Drop uploaded", forBadgeIdentifier: successBadgeIdentifier)
        controller.setBadgeImage(Self.badgeIcon(systemSymbolName: "xmark.circle.fill", fallbackText: "!"), label: "Agent Drop failed", forBadgeIdentifier: failureBadgeIdentifier)
    }

    private static func markFiles(_ files: [URL], badgeIdentifier: String) {
        DispatchQueue.main.async {
            let controller = FIFinderSyncController.default()
            for file in files {
                controller.setBadgeIdentifier(badgeIdentifier, for: file)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                for file in files {
                    controller.setBadgeIdentifier("", for: file)
                }
            }
        }
    }

    private static func menuIcon() -> NSImage {
        let image = NSImage(named: "AgentDropMenuIcon")
            ?? NSImage(systemSymbolName: "tray.and.arrow.up", accessibilityDescription: "Agent Drop")
            ?? Self.textIcon("⇧")
        image.isTemplate = true
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    private static func badgeIcon(systemSymbolName: String, fallbackText: String) -> NSImage {
        let image = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: nil)
            ?? Self.textIcon(fallbackText)
        image.isTemplate = true
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    private static func textIcon(_ text: String) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedText.size()
        attributedText.draw(at: NSPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2))
        image.unlockFocus()
        return image
    }

    private static func copyToPasteboard(_ text: String) -> Bool {
        var succeeded = false
        DispatchQueue.main.sync {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            succeeded = pasteboard.setString(text, forType: .string)
        }
        return succeeded
    }

    private static func accountHomePath() -> String? {
        getpwuid(getuid()).flatMap { passwd in
            guard let home = passwd.pointee.pw_dir else {
                return nil
            }
            guard home[0] != 0 else { return nil }
            return String(cString: home)
        }
    }

    private static func recordHistory(_ entry: UploadHistoryEntry, store: UploadHistoryStore) {
        do {
            try store.append(entry)
            recordDiagnostic("history recorded id=\(entry.id.uuidString) status=\(entry.status.rawValue)")
        } catch {
            recordDiagnostic("history failed id=\(entry.id.uuidString) error=\(String(describing: error))")
        }
    }

    private static func recordDiagnostic(_ message: String) {
        let fileManager = FileManager.default
        let libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let logDirectory = libraryURL.appendingPathComponent("Logs", isDirectory: true)
        let logURL = logDirectory.appendingPathComponent("AgentDropFinderSync.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        let data = Data(line.utf8)

        do {
            try fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: logURL)
            }
        } catch {
            logger.error("Failed to write Finder Sync diagnostic: \(String(describing: error), privacy: .public)")
        }
    }
}
