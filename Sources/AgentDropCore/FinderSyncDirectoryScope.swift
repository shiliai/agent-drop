import Foundation

public enum HostHomeDirectoryResolver {
    public static func resolve(accountHomePath: String?, fallback: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        guard let accountHomePath, !accountHomePath.isEmpty else {
            return fallback
        }

        return URL(fileURLWithPath: accountHomePath, isDirectory: true)
    }
}

public enum FinderSyncDirectoryScope {
    public static func monitoredDirectories(home: URL) -> [URL] {
        var homes = [home]
        if home.path.hasPrefix("/Users/") {
            homes.append(URL(fileURLWithPath: "/System/Volumes/Data\(home.path)", isDirectory: true))
        }

        var directories: [URL] = []
        for base in homes {
            directories.append(base)
            directories.append(base.appendingPathComponent("Desktop", isDirectory: true))
            directories.append(base.appendingPathComponent("Documents", isDirectory: true))
            directories.append(base.appendingPathComponent("Downloads", isDirectory: true))
        }
        directories.append(URL(fileURLWithPath: "/Volumes", isDirectory: true))
        return directories
    }
}
