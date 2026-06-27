import XCTest
@testable import AgentDropCore

final class PullFormPrefillTests: XCTestCase {
    func testPrefillsPlainRemotePathWithoutChangingTarget() {
        let result = PullFormPrefill.evaluate(
            clipboardText: "  ~/runs/output.png  ",
            targets: [SSHTarget(name: "devbox", source: .config)]
        )

        XCTAssertEqual(result, PullFormPrefill.Result(selectedTargetID: nil, pathText: "~/runs/output.png"))
    }

    func testSelectsTargetAndPreservesHostHintForMatchingTargetName() {
        let target = SSHTarget(name: "devbox", source: .config)

        let result = PullFormPrefill.evaluate(
            clipboardText: "devbox:~/runs/output.png",
            targets: [target]
        )

        XCTAssertEqual(result, PullFormPrefill.Result(selectedTargetID: target.id, pathText: "devbox:~/runs/output.png"))
    }

    func testSelectsTargetAndPreservesHostHintForMatchingConnectName() {
        let target = SSHTarget(name: "GPU Box", connectName: "gpu-box.internal", source: .config)

        let result = PullFormPrefill.evaluate(
            clipboardText: "gpu-box.internal:/tmp/result.zip",
            targets: [target]
        )

        XCTAssertEqual(result, PullFormPrefill.Result(selectedTargetID: target.id, pathText: "gpu-box.internal:/tmp/result.zip"))
    }

    func testPreservesMultipleHostHintsWhenTheyAllMatchOneTarget() {
        let target = SSHTarget(name: "devbox", source: .config)

        let result = PullFormPrefill.evaluate(
            clipboardText: """
            devbox:~/runs/output.png
            devbox:/tmp/build-artifacts
            """,
            targets: [target]
        )

        XCTAssertEqual(
            result,
            PullFormPrefill.Result(
                selectedTargetID: target.id,
                pathText: "devbox:~/runs/output.png\ndevbox:/tmp/build-artifacts"
            )
        )
    }

    func testKeepsUsableTextAndDoesNotSelectTargetWhenHostHintsDiffer() {
        let result = PullFormPrefill.evaluate(
            clipboardText: """
            devbox:~/runs/output.png
            gpu-box:/tmp/build-artifacts
            """,
            targets: [
                SSHTarget(name: "devbox", source: .config),
                SSHTarget(name: "gpu-box", source: .config)
            ]
        )

        XCTAssertEqual(
            result,
            PullFormPrefill.Result(
                selectedTargetID: nil,
                pathText: "devbox:~/runs/output.png\ngpu-box:/tmp/build-artifacts"
            )
        )
    }

    func testRejectsRandomProse() {
        let result = PullFormPrefill.evaluate(
            clipboardText: "Please download the latest result when you can.",
            targets: [SSHTarget(name: "devbox", source: .config)]
        )

        XCTAssertNil(result)
    }
}
