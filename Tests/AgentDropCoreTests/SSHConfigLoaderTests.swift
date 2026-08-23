import Foundation
import XCTest
@testable import AgentDropCore

final class SSHConfigLoaderTests: XCTestCase {
    func testLoadsHostsFromIncludedFile() throws {
        let homeURL = try makeHomeDirectory()
        defer { try? FileManager.default.removeItem(at: homeURL) }

        try write("Include ~/.ssh/config.d/reverse-tunnels\nHost devbox\n", to: homeURL, path: ".ssh/config")
        try write("Host tunnel-box\n", to: homeURL, path: ".ssh/config.d/reverse-tunnels")

        let targets = SSHConfigLoader().loadTargets(homeDirectoryURL: homeURL)

        XCTAssertEqual(targets.map(\.name), ["tunnel-box", "devbox"])
    }

    func testExpandsRelativeWildcardIncludesInLexicalOrder() throws {
        let homeURL = try makeHomeDirectory()
        defer { try? FileManager.default.removeItem(at: homeURL) }

        try write("Include config.d/*\n", to: homeURL, path: ".ssh/config")
        try write("Host second\n", to: homeURL, path: ".ssh/config.d/20-second")
        try write("Host first\n", to: homeURL, path: ".ssh/config.d/10-first")

        let targets = SSHConfigLoader().loadTargets(homeDirectoryURL: homeURL)

        XCTAssertEqual(targets.map(\.name), ["first", "second"])
    }

    func testSupportsQuotedIncludePathsAndStopsIncludeCycles() throws {
        let homeURL = try makeHomeDirectory()
        defer { try? FileManager.default.removeItem(at: homeURL) }

        try write("Include \"config.d/team hosts\"\nHost root\n", to: homeURL, path: ".ssh/config")
        try write("Include config\nHost team-box\n", to: homeURL, path: ".ssh/config.d/team hosts")

        let targets = SSHConfigLoader().loadTargets(homeDirectoryURL: homeURL)

        XCTAssertEqual(targets.map(\.name), ["team-box", "root"])
    }

    private func makeHomeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, to homeURL: URL, path: String) throws {
        let url = homeURL.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
