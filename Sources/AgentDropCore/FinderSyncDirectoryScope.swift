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
        monitoredDirectories(home: home, mountedVolumes: mountedVolumeDirectories())
    }

    public static func monitoredDirectories(home: URL, mountedVolumes: [URL]) -> [URL] {
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
        directories.append(contentsOf: mountedVolumes)
        return uniqueDirectories(directories)
    }

    public static func mountedVolumeDirectories(
        fileManager: FileManager = .default
    ) -> [URL] {
        fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]
        )?
        .filter { $0.path.hasPrefix("/Volumes/") }
        .map { $0.standardizedFileURL }
        ?? []
    }

    private static func uniqueDirectories(_ directories: [URL]) -> [URL] {
        var seen = Set<String>()
        var unique: [URL] = []

        for directory in directories {
            let standardized = directory.standardizedFileURL
            guard seen.insert(standardized.path).inserted else { continue }
            unique.append(standardized)
        }

        return unique
    }
}
