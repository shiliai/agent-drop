import XCTest
@testable import AgentDropCore

final class FinderExtensionAvailabilityTests: XCTestCase {
    func testParsesEnabledFinderExtensionFromPluginkitOutput() {
        let output = """
        +    com.synology.SynologyDrive.FinderHelper.FinderSync(1.0)
             com.microsoft.OneDrive-mac.FinderSync(26.084.0504)
        +    ai.shili.AgentDrop.FinderSync(0.2.4)
        """

        let availability = FinderExtensionAvailability.parse(pluginkitOutput: output)

        XCTAssertEqual(availability.status, .enabled)
        XCTAssertEqual(availability.bundleIdentifier, "ai.shili.AgentDrop.FinderSync")
    }

    func testParsesRegisteredButDisabledFinderExtensionFromPluginkitOutput() {
        let output = """
             ai.shili.AgentDrop.FinderSync(0.2.4)
        +    com.synology.SynologyDrive.FinderHelper.FinderSync(1.0)
        """

        let availability = FinderExtensionAvailability.parse(pluginkitOutput: output)

        XCTAssertEqual(availability.status, .disabled)
    }

    func testParsesMissingFinderExtensionFromPluginkitOutput() {
        let output = """
        +    com.synology.SynologyDrive.FinderHelper.FinderSync(1.0)
             com.microsoft.OneDrive-mac.FinderSync(26.084.0504)
        """

        let availability = FinderExtensionAvailability.parse(pluginkitOutput: output)

        XCTAssertEqual(availability.status, .notRegistered)
    }

    func testIgnoresSimilarlyNamedFinderExtensions() {
        let output = """
        +    ai.shili.AgentDrop.FinderSyncBeta(1.0)
             dev.ai.shili.AgentDrop.FinderSync(1.0)
        """

        let availability = FinderExtensionAvailability.parse(pluginkitOutput: output)

        XCTAssertEqual(availability.status, .notRegistered)
    }

    func testCheckReturnsUnknownWhenPluginkitCommandThrows() {
        let runner = StubCommandRunner(error: StubCommandError(message: "pluginkit failed"))

        let availability = FinderExtensionAvailabilityChecker.check(runner: runner)

        XCTAssertEqual(availability.status, .unknown("pluginkit failed"))
        XCTAssertEqual(runner.invocations, [
            CommandInvocation(
                executable: "/usr/bin/pluginkit",
                arguments: ["-m", "-A", "-p", "com.apple.FinderSync"]
            )
        ])
    }

    func testCheckReturnsUnknownWhenPluginkitCommandExitsNonZero() {
        let runner = StubCommandRunner(result: .failure(exitCode: 1, stdout: "", stderr: "pluginkit failed"))

        let availability = FinderExtensionAvailabilityChecker.check(runner: runner)

        XCTAssertEqual(availability.status, .unknown("pluginkit failed"))
        XCTAssertEqual(runner.invocations, [
            CommandInvocation(
                executable: "/usr/bin/pluginkit",
                arguments: ["-m", "-A", "-p", "com.apple.FinderSync"]
            )
        ])
    }

    func testCheckParsesCommandOutput() {
        let runner = StubCommandRunner(result: .success(
            stdout: "+    ai.shili.AgentDrop.FinderSync(0.2.4)\n",
            stderr: ""
        ))

        let availability = FinderExtensionAvailabilityChecker.check(runner: runner)

        XCTAssertEqual(availability.status, .enabled)
    }
}

private final class StubCommandRunner: CommandRunning {
    private let result: CommandResult?
    private let error: Error?
    var invocations: [CommandInvocation] = []

    init(result: CommandResult) {
        self.result = result
        self.error = nil
    }

    init(error: Error) {
        self.result = nil
        self.error = error
    }

    func run(_ invocation: CommandInvocation) throws -> CommandResult {
        invocations.append(invocation)
        if let error {
            throw error
        }
        return result!
    }
}

private struct StubCommandError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
