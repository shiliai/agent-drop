import XCTest
@testable import AgentDropCore

final class DoctorTests: XCTestCase {
    func testReportsMissingRequiredTool() {
        let doctor = Doctor(toolLookup: { tool in tool == "ssh" ? "/usr/bin/ssh" : nil })

        let report = doctor.run()

        XCTAssertEqual(report.checks.first(where: { $0.name == "ssh" })?.status, .ok)
        XCTAssertEqual(report.checks.first(where: { $0.name == "rsync" })?.status, .missing)
        XCTAssertEqual(report.checks.first(where: { $0.name == "pbcopy" })?.status, .missing)
    }
}
