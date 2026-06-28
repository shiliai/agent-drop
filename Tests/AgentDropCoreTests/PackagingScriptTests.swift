import XCTest

final class PackagingScriptTests: XCTestCase {
    func testDeveloperDMGScriptExistsAndUsesExpectedInstallerLayout() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/package_developer_dmg.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        let attributes = try FileManager.default.attributesOfItem(atPath: scriptURL.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue

        XCTAssertNotEqual(permissions & 0o111, 0)
        XCTAssertTrue(script.contains("/usr/bin/ditto"))
        XCTAssertTrue(script.contains("/Applications"))
        XCTAssertTrue(script.contains("hdiutil create"))
        XCTAssertTrue(script.contains("hdiutil attach"))
        XCTAssertTrue(script.contains("AgentDrop-developer.dmg"))
    }
}

private func repositoryRoot(
    file: StaticString = #filePath
) -> URL {
    URL(fileURLWithPath: "\(file)")
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
