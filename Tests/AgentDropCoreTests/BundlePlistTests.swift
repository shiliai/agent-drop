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

    func testAppEntitlementsKeepContainingAppUnsandboxedForDeveloperHistoryAccess() throws {
        let entitlements = try loadPlist("Sources/AgentDropApp/AgentDrop.entitlements")

        XCTAssertNil(entitlements["com.apple.security.app-sandbox"])
        XCTAssertNil(entitlements["com.apple.security.network.client"])
    }

    func testFinderExtensionEntitlementsSupportDevelopmentSigning() throws {
        let entitlements = try loadPlist("Sources/AgentDropFinderSync/AgentDropFinderSync.entitlements")

        XCTAssertEqual(entitlements["com.apple.security.app-sandbox"] as? Bool, true)
        XCTAssertEqual(entitlements["com.apple.security.network.client"] as? Bool, true)
        XCTAssertEqual(entitlements["com.apple.security.files.user-selected.read-only"] as? Bool, true)
        XCTAssertEqual(
            entitlements["com.apple.security.temporary-exception.files.absolute-path.read-only"] as? [String],
            ["/Users/chris/", "/Users/chris/.ssh/"]
        )
    }

    private func loadPlist(_ relativePath: String) throws -> [String: Any] {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        let value = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(value as? [String: Any])
    }
}
