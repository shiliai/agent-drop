import XCTest
@testable import AgentDropCore

final class TargetResolverTests: XCTestCase {
    func testActiveTargetsSortBeforeConfigOnlyTargets() {
        let active = [SSHTarget(name: "devbox", source: .active)]
        let configured = [
            SSHTarget(name: "devbox", source: .config),
            SSHTarget(name: "work-ubuntu", source: .config)
        ]

        let resolved = TargetResolver.merge(active: active, configured: configured)

        XCTAssertEqual(resolved.map(\.name), ["devbox", "work-ubuntu"])
        XCTAssertEqual(resolved.map(\.source), [.active, .config])
    }
}
