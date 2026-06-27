import XCTest
@testable import AgentDropCore

final class AgentDropRouteTests: XCTestCase {
    func testParsesPullRouteFromCustomSchemeHost() {
        let route = AgentDropRoute(url: URL(string: "agentdrop://pull")!)

        XCTAssertEqual(route, .pull)
    }

    func testParsesPullRouteFromCustomSchemePath() {
        let route = AgentDropRoute(url: URL(string: "agentdrop:/pull")!)

        XCTAssertEqual(route, .pull)
    }

    func testRejectsUnknownCustomSchemeRoute() {
        let route = AgentDropRoute(url: URL(string: "agentdrop://history")!)

        XCTAssertNil(route)
    }

    func testRejectsNonAgentDropScheme() {
        let route = AgentDropRoute(url: URL(string: "https://example.com/pull")!)

        XCTAssertNil(route)
    }
}
