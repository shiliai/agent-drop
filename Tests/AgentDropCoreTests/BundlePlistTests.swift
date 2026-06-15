import XCTest

final class BundlePlistTests: XCTestCase {
    func testAppPlistDeclaresExecutable() throws {
        let plist = try loadPlist("Sources/AgentDropApp/Info.plist")

        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "AgentDrop")
    }

    func testAppPlistDeclaresIconName() throws {
        let plist = try loadPlist("Sources/AgentDropApp/Info.plist")

        XCTAssertEqual(plist["CFBundleIconName"] as? String, "AppIcon")
    }

    func testFinderExtensionPlistDeclaresExecutable() throws {
        let plist = try loadPlist("Sources/AgentDropFinderSync/Info.plist")

        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "$(EXECUTABLE_NAME)")
    }

    private func loadPlist(_ relativePath: String) throws -> [String: Any] {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        let value = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(value as? [String: Any])
    }
}
