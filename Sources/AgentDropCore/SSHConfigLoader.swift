import Darwin
import Foundation

public struct SSHConfigLoader {
    public init() {}

    public func loadTargets(homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser) -> [SSHTarget] {
        let sshDirectoryURL = homeDirectoryURL.appendingPathComponent(".ssh", isDirectory: true)
        let configURL = sshDirectoryURL.appendingPathComponent("config", isDirectory: false)
        var visitedURLs = Set<URL>()

        return loadTargets(
            from: configURL,
            homeDirectoryURL: homeDirectoryURL,
            sshDirectoryURL: sshDirectoryURL,
            visitedURLs: &visitedURLs
        )
    }

    private func loadTargets(
        from configURL: URL,
        homeDirectoryURL: URL,
        sshDirectoryURL: URL,
        visitedURLs: inout Set<URL>
    ) -> [SSHTarget] {
        let resolvedURL = configURL.standardizedFileURL.resolvingSymlinksInPath()
        guard visitedURLs.insert(resolvedURL).inserted,
              let configText = try? String(contentsOf: resolvedURL, encoding: .utf8) else {
            return []
        }

        var targets: [SSHTarget] = []

        for rawLine in configText.split(separator: "\n", omittingEmptySubsequences: false) {
            let fields = SSHConfigTokenizer.fields(in: String(rawLine))
            guard let keyword = fields.first?.lowercased() else { continue }

            if keyword == "host" {
                targets.append(contentsOf: SSHConfigParser().parse(String(rawLine)))
                continue
            }

            guard keyword == "include" else { continue }
            for pattern in fields.dropFirst() {
                for includeURL in matchingURLs(
                    for: pattern,
                    homeDirectoryURL: homeDirectoryURL,
                    sshDirectoryURL: sshDirectoryURL
                ) {
                    targets.append(contentsOf: loadTargets(
                        from: includeURL,
                        homeDirectoryURL: homeDirectoryURL,
                        sshDirectoryURL: sshDirectoryURL,
                        visitedURLs: &visitedURLs
                    ))
                }
            }
        }

        return targets
    }

    private func matchingURLs(
        for pattern: String,
        homeDirectoryURL: URL,
        sshDirectoryURL: URL
    ) -> [URL] {
        let expandedPattern: String
        if pattern == "~" {
            expandedPattern = homeDirectoryURL.path
        } else if pattern.hasPrefix("~/") {
            expandedPattern = homeDirectoryURL.appendingPathComponent(String(pattern.dropFirst(2))).path
        } else if pattern.hasPrefix("/") {
            expandedPattern = pattern
        } else {
            expandedPattern = sshDirectoryURL.appendingPathComponent(pattern).path
        }

        var matches = glob_t()
        defer { globfree(&matches) }

        guard glob(expandedPattern, GLOB_TILDE, nil, &matches) == 0,
              let paths = matches.gl_pathv else {
            return []
        }

        return (0..<Int(matches.gl_pathc)).compactMap { index in
            guard let path = paths[index] else { return nil }
            return URL(fileURLWithPath: String(cString: path), isDirectory: false)
        }
    }
}
