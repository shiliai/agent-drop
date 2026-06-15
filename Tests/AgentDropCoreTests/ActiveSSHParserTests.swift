import XCTest
@testable import AgentDropCore

final class ActiveSSHParserTests: XCTestCase {
    func testParsesAliasFromSSHCommand() {
        let lines = [
            "ssh devbox",
            "ssh -A gpu-box",
            "ssh -p 2222 ubuntu@192.168.1.24"
        ]

        let targets = ActiveSSHParser().parseProcessCommands(lines)

        XCTAssertEqual(targets.map(\.connectName), ["devbox", "gpu-box", "ubuntu@192.168.1.24"])
        XCTAssertEqual(targets.map(\.source), [.active, .active, .active])
    }

    func testIgnoresSCPAndRemoteCommandsWithoutHost() {
        let lines = [
            "scp file devbox:/tmp",
            "ssh",
            "ssh -N -L 8080:localhost:80 devbox"
        ]

        let targets = ActiveSSHParser().parseProcessCommands(lines)

        XCTAssertEqual(targets.map(\.connectName), ["devbox"])
    }

    func testParsesPathInvokedSSHAndQuotedOptionValues() {
        let lines = [
            "/usr/bin/ssh devbox",
            "ssh -o ProxyCommand='ssh jump %h %p' work-ubuntu"
        ]

        let targets = ActiveSSHParser().parseProcessCommands(lines)

        XCTAssertEqual(targets.map(\.connectName), ["devbox", "work-ubuntu"])
    }

    func testSkipsValueTakingOptionsBeforeHost() {
        let lines = [
            "ssh -F ~/.ssh/alt_config devbox",
            "ssh -S /tmp/ssh-control work-ubuntu"
        ]

        let targets = ActiveSSHParser().parseProcessCommands(lines)

        XCTAssertEqual(targets.map(\.connectName), ["devbox", "work-ubuntu"])
    }
}
