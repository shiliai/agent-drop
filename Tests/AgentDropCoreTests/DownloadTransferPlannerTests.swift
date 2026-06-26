import XCTest
@testable import AgentDropCore

final class DownloadTransferPlannerTests: XCTestCase {
    func testBuildsRemoteInspectionCommandWithSafeQuoting() {
        let invocation = DownloadTransferPlanner.remoteInspectionCommand(
            target: SSHTarget(name: "devbox", source: .config),
            remotePath: "~/runs/client's output"
        )

        XCTAssertEqual(invocation, CommandInvocation(
            executable: "/usr/bin/ssh",
            arguments: [
                "devbox",
                "if [ -f $HOME/'runs/client'\"'\"'s output' ]; then printf 'file\\n'; elif [ -d $HOME/'runs/client'\"'\"'s output' ]; then printf 'directory\\n'; find $HOME/'runs/client'\"'\"'s output' -type f | wc -l; else exit 2; fi"
            ]
        ))
    }

    func testPlansTransferStrategyFromRemoteFacts() {
        XCTAssertEqual(DownloadTransferPlanner.strategy(for: .file), .rsyncFile)
        XCTAssertEqual(DownloadTransferPlanner.strategy(for: .directory(fileCount: 200)), .rsyncDirectory)
        XCTAssertEqual(DownloadTransferPlanner.strategy(for: .directory(fileCount: 201)), .tarStream)
    }

    func testBuildsRsyncFileCommandWithQuotedRemotePath() {
        let reserved = ReservedLocalDestination(
            url: URL(fileURLWithPath: "/Users/chris/Downloads/Agent Drop/output file.png"),
            kind: .file
        )
        let plan = DownloadTransferPlanner.plan(
            target: SSHTarget(name: "devbox", source: .config),
            remotePath: "~/runs/output file.png",
            kind: .file,
            reservedDestination: reserved
        )

        XCTAssertEqual(plan.strategy, .rsyncFile)
        XCTAssertEqual(plan.invocations, [
            CommandInvocation(
                executable: "/usr/bin/rsync",
                arguments: ["-a", "devbox:$HOME/'runs/output file.png'", "/Users/chris/Downloads/Agent Drop/output file.png"]
            )
        ])
    }

    func testBuildsRsyncDirectoryCommandWithTrailingSlashes() {
        let reserved = ReservedLocalDestination(
            url: URL(fileURLWithPath: "/Users/chris/Downloads/Agent Drop/build-artifacts", isDirectory: true),
            kind: .directory
        )
        let plan = DownloadTransferPlanner.plan(
            target: SSHTarget(name: "devbox", source: .config),
            remotePath: "/tmp/build-artifacts",
            kind: .directory(fileCount: 200),
            reservedDestination: reserved
        )

        XCTAssertEqual(plan.strategy, .rsyncDirectory)
        XCTAssertEqual(plan.invocations, [
            CommandInvocation(
                executable: "/usr/bin/rsync",
                arguments: ["-a", "devbox:'/tmp/build-artifacts'/", "/Users/chris/Downloads/Agent Drop/build-artifacts/"]
            )
        ])
    }

    func testBuildsTarStreamInvocationsWithShellQuoting() {
        let reserved = ReservedLocalDestination(
            url: URL(fileURLWithPath: "/Users/chris/Downloads/Agent Drop/client reports", isDirectory: true),
            kind: .directory
        )
        let plan = DownloadTransferPlanner.plan(
            target: SSHTarget(name: "devbox", source: .config),
            remotePath: "/tmp/client's reports",
            kind: .directory(fileCount: 201),
            reservedDestination: reserved
        )

        XCTAssertEqual(plan.strategy, .tarStream)
        XCTAssertEqual(plan.invocations, [
            CommandInvocation(
                executable: "/usr/bin/ssh",
                arguments: ["devbox", "tar -C '/tmp/client'\"'\"'s reports' -czf - ."]
            ),
            CommandInvocation(
                executable: "/usr/bin/tar",
                arguments: ["-xzf", "-", "-C", "/Users/chris/Downloads/Agent Drop/client reports"]
            )
        ])
    }
}
