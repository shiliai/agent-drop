import XCTest
@testable import AgentDropCore

final class SSHConfigParserTests: XCTestCase {
    func testParsesSimpleHostAliases() {
        let config = """
        Host devbox
          HostName 192.168.1.20
          User chris

        Host gpu-box work-ubuntu
          User ubuntu
        """

        let targets = SSHConfigParser().parse(config)

        XCTAssertEqual(targets.map(\.name), ["devbox", "gpu-box", "work-ubuntu"])
        XCTAssertEqual(targets.map(\.source), [.config, .config, .config])
    }

    func testIgnoresWildcardHosts() {
        let config = """
        Host *
          ServerAliveInterval 30

        Host devbox
          HostName 192.168.1.20
        """

        let targets = SSHConfigParser().parse(config)

        XCTAssertEqual(targets.map(\.name), ["devbox"])
    }
}
