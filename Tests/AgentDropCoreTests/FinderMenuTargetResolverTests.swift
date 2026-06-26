import XCTest
@testable import AgentDropCore

final class FinderMenuTargetResolverTests: XCTestCase {
    func testUsesRepresentedObjectWhenPresent() {
        let name = FinderMenuTargetResolver.connectName(representedObject: "x570", title: "ignored    config")

        XCTAssertEqual(name, "x570")
    }

    func testFallsBackToMenuTitleWithoutSourceSuffix() {
        let name = FinderMenuTargetResolver.connectName(representedObject: nil, title: "x570    config")

        XCTAssertEqual(name, "x570")
    }

    func testRejectsBlankTitleWhenRepresentedObjectMissing() {
        let name = FinderMenuTargetResolver.connectName(representedObject: nil, title: "    ")

        XCTAssertNil(name)
    }
}
