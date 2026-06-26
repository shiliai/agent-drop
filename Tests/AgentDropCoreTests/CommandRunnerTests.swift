import Darwin
import XCTest
@testable import AgentDropCore

final class CommandRunnerTests: XCTestCase {
    func testLaunchFailureDoesNotLeaveBlockedPipeReadersAndAllowsSubsequentRuns() throws {
        let runner = ProcessCommandRunner()
        let threadCountBefore = try currentThreadCount()

        for _ in 0..<8 {
            XCTAssertThrowsError(try runner.run(CommandInvocation(
                executable: "/tmp/agent-drop-definitely-missing-command",
                arguments: []
            )))
        }

        Thread.sleep(forTimeInterval: 0.1)
        let threadCountAfterFailures = try currentThreadCount()

        let result = try runner.run(CommandInvocation(
            executable: "/bin/echo",
            arguments: ["still-runs"]
        ))

        XCTAssertLessThanOrEqual(threadCountAfterFailures - threadCountBefore, 4)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "still-runs\n")
        XCTAssertEqual(result.stderr, "")
    }

    func testDrainsLargeStdoutWhilePreservingStderrAndStandardInput() throws {
        let outputSize = 2 * 1024 * 1024
        let script = """
        alarm 5;
        print "x" x \(outputSize);
        print STDERR "captured-stderr";
        my $input = <STDIN>;
        chomp $input;
        print "stdin:$input";
        """

        let result = try ProcessCommandRunner().run(CommandInvocation(
            executable: "/usr/bin/perl",
            arguments: ["-e", script],
            standardInput: "captured-stdin\n"
        ))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.count, outputSize + "stdin:captured-stdin".count)
        XCTAssertTrue(result.stdout.hasPrefix("xxx"))
        XCTAssertTrue(result.stdout.hasSuffix("stdin:captured-stdin"))
        XCTAssertEqual(result.stderr, "captured-stderr")
    }
}

private func currentThreadCount() throws -> Int {
    var info = proc_taskallinfo()
    let expectedSize = MemoryLayout<proc_taskallinfo>.size
    let actualSize = proc_pidinfo(getpid(), PROC_PIDTASKALLINFO, 0, &info, Int32(expectedSize))

    guard actualSize == expectedSize else {
        throw NSError(domain: "CommandRunnerTests", code: Int(actualSize))
    }

    return Int(info.ptinfo.pti_threadnum)
}
