import XCTest
@testable import AgentDropCore

final class DoctorTests: XCTestCase {
    func testReportsMissingRequiredTool() {
        let doctor = Doctor(toolLookup: { tool in tool == "ssh" ? "/usr/bin/ssh" : nil })

        let report = doctor.run()

        XCTAssertEqual(report.checks.first(where: { $0.name == "ssh" })?.status, .ok)
        XCTAssertEqual(report.checks.first(where: { $0.name == "rsync" })?.status, .missing)
        XCTAssertEqual(report.checks.first(where: { $0.name == "tar" })?.status, .missing)
        XCTAssertEqual(report.checks.first(where: { $0.name == "pbcopy" })?.status, .missing)
    }

    func testDependencyFeedbackFiltersMissingToolsByTransferRequirement() {
        let doctor = Doctor(toolLookup: { tool in
            switch tool {
            case "ssh", "pbcopy":
                return "/usr/bin/\(tool)"
            default:
                return nil
            }
        })
        let report = doctor.run()

        let uploadFeedback = DependencyFeedback.missingFeedback(in: report, for: .finderUpload)
        let pullFeedback = DependencyFeedback.missingFeedback(in: report, for: .appPull)

        XCTAssertEqual(uploadFeedback?.missingToolNames, ["rsync"])
        XCTAssertEqual(pullFeedback?.missingToolNames, ["rsync", "tar"])
    }

    func testFinderUploadDependencyFeedbackDoesNotRequirePBClipboardTool() {
        let doctor = Doctor(toolLookup: { tool in
            switch tool {
            case "ssh", "rsync":
                return "/usr/bin/\(tool)"
            default:
                return nil
            }
        })
        let report = doctor.run()

        XCTAssertNil(DependencyFeedback.missingFeedback(in: report, for: .finderUpload))
    }

    func testAppDropDependencyFeedbackRequiresPBClipboardTool() {
        let doctor = Doctor(toolLookup: { tool in
            switch tool {
            case "ssh", "rsync":
                return "/usr/bin/\(tool)"
            default:
                return nil
            }
        })
        let report = doctor.run()

        XCTAssertEqual(DependencyFeedback.missingFeedback(in: report, for: .appDrop)?.missingToolNames, ["pbcopy"])
    }

    func testDependencyFeedbackMessageDoesNotOfferAutomaticInstall() {
        let feedback = DependencyFeedback(missingToolNames: ["rsync"])

        XCTAssertEqual(
            feedback.message,
            "Missing required local tool: rsync. Install it and try again. Agent Drop does not install dependencies automatically."
        )
    }

    func testDependencyFeedbackMessageHandlesMultipleMissingTools() {
        let feedback = DependencyFeedback(missingToolNames: ["rsync", "tar"])

        XCTAssertEqual(
            feedback.message,
            "Missing required local tools: rsync, tar. Install them and try again. Agent Drop does not install dependencies automatically."
        )
    }

    func testDependencyFeedbackProviderRerunsDoctorForEachRequest() {
        var reports = [
            DoctorReport(checks: [
                DoctorCheck(name: "ssh", status: .ok),
                DoctorCheck(name: "rsync", status: .missing),
                DoctorCheck(name: "tar", status: .ok),
                DoctorCheck(name: "pbcopy", status: .ok)
            ]),
            DoctorReport(checks: [
                DoctorCheck(name: "ssh", status: .ok),
                DoctorCheck(name: "rsync", status: .ok),
                DoctorCheck(name: "tar", status: .ok),
                DoctorCheck(name: "pbcopy", status: .ok)
            ])
        ]
        var runCount = 0
        let provider = DependencyFeedbackProvider {
            runCount += 1
            return reports.removeFirst()
        }

        XCTAssertEqual(provider.feedback(for: .appPull)?.missingToolNames, ["rsync"])
        XCTAssertNil(provider.feedback(for: .appPull))
        XCTAssertEqual(runCount, 2)
    }
}
