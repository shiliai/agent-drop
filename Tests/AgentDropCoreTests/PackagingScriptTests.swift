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

    func testDefaultAppSelectionUsesMostRecentlyModifiedDebugBuild() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/package_developer_dmg.sh")
        let home = try temporaryDirectory()
        let derivedData = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        let oldApp = derivedData.appendingPathComponent("AgentDrop-ZZZ/Build/Products/Debug/AgentDrop.app")
        let newApp = derivedData.appendingPathComponent("AgentDrop-AAA/Build/Products/Debug/AgentDrop.app")

        try FileManager.default.createDirectory(at: oldApp, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newApp, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)],
            ofItemAtPath: oldApp.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_800_000_000)],
            ofItemAtPath: newApp.path
        )

        let output = try runShell(
            """
            HOME='\(shellEscape(home.path))'
            source '\(shellEscape(scriptURL.path))'
            find_default_app
            """
        )

        XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), newApp.path)
    }

    func testExitCleanupRemovesStagingAndMountDirectories() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/package_developer_dmg.sh")
        let temp = try temporaryDirectory()
        let staging = temp.appendingPathComponent("dmg-staging")
        let mount = temp.appendingPathComponent("dmg-mounted")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)

        _ = try runShell(
            """
            source '\(shellEscape(scriptURL.path))'
            STAGING_DIR='\(shellEscape(staging.path))'
            MOUNT_POINT='\(shellEscape(mount.path))'
            trap cleanup EXIT
            exit 42
            """,
            expectedExitCode: 42
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: mount.path))
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

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AgentDropPackagingScriptTests")
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func runShell(
    _ command: String,
    expectedExitCode: Int32 = 0,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-c", command]

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    try process.run()
    process.waitUntilExit()

    let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

    XCTAssertEqual(
        process.terminationStatus,
        expectedExitCode,
        "stdout:\n\(output)\nstderr:\n\(error)",
        file: file,
        line: line
    )
    return output
}

private func shellEscape(_ value: String) -> String {
    value.replacingOccurrences(of: "'", with: "'\\''")
}
