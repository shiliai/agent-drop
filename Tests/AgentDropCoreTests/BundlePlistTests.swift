import XCTest
@testable import AgentDropCore

final class BundlePlistTests: XCTestCase {
    func testAppPlistDeclaresExecutable() throws {
        let plist = try loadPlist("Sources/AgentDropApp/Info.plist")

        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "AgentDrop")
    }

    func testAppPlistDeclaresIconName() throws {
        let plist = try loadPlist("Sources/AgentDropApp/Info.plist")

        XCTAssertEqual(plist["CFBundleIconName"] as? String, "AppIcon")
    }

    func testAppPlistRegistersAgentDropURLScheme() throws {
        let plist = try loadPlist("Sources/AgentDropApp/Info.plist")
        let urlTypes = try XCTUnwrap(plist["CFBundleURLTypes"] as? [[String: Any]])
        let agentDropURLType = try XCTUnwrap(urlTypes.first { urlType in
            (urlType["CFBundleURLName"] as? String) == "ai.shili.AgentDrop.route"
        })

        XCTAssertEqual(agentDropURLType["CFBundleURLSchemes"] as? [String], ["agentdrop"])
    }

    func testFinderExtensionPlistDeclaresExecutable() throws {
        let plist = try loadPlist("Sources/AgentDropFinderSync/Info.plist")

        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "$(EXECUTABLE_NAME)")
    }

    func testAppAndFinderExtensionDeclareMatchingVersionAndBuild() throws {
        let appPlist = try loadPlist("Sources/AgentDropApp/Info.plist")
        let finderExtensionPlist = try loadPlist("Sources/AgentDropFinderSync/Info.plist")

        let appVersion = try XCTUnwrap(appPlist["CFBundleShortVersionString"] as? String)
        let finderExtensionVersion = try XCTUnwrap(
            finderExtensionPlist["CFBundleShortVersionString"] as? String
        )
        let appBuild = try XCTUnwrap(appPlist["CFBundleVersion"] as? String)
        let finderExtensionBuild = try XCTUnwrap(finderExtensionPlist["CFBundleVersion"] as? String)

        XCTAssertEqual(appVersion, AgentDropVersion.current)
        XCTAssertEqual(finderExtensionVersion, appVersion)
        XCTAssertEqual(appBuild, AgentDropVersion.build)
        XCTAssertEqual(finderExtensionBuild, appBuild)
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
            ["/Users/chris/", "/Users/chris/.ssh/", "/Volumes/"]
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
