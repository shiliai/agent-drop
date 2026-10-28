import XCTest
@testable import AgentDropCore

final class TransferNavigationStateTests: XCTestCase {
    func testDefaultsToTransferWithDropDirection() {
        let state = TransferNavigationState()

        XCTAssertEqual(state.selectedSection, .transfer)
        XCTAssertEqual(state.transferMode, .drop)
        XCTAssertNil(state.selectedTargetID)
    }

    func testPullRouteSelectsTransferWithPullDirection() {
        var state = TransferNavigationState(selectedSection: .activity, transferMode: .drop)

        state.apply(.pull)

        XCTAssertEqual(state.selectedSection, .transfer)
        XCTAssertEqual(state.transferMode, .pull)
    }

    func testActivitySelectionDoesNotResetTransferDirection() {
        var state = TransferNavigationState(selectedSection: .transfer, transferMode: .pull)

        state.selectedSection = .activity
        state.selectedSection = .transfer

        XCTAssertEqual(state.transferMode, .pull)
    }

    func testSectionsDeclareStableContextColumnTitles() {
        XCTAssertEqual(AppSection.transfer.contextColumnTitle, "Hosts")
        XCTAssertEqual(AppSection.activity.contextColumnTitle, "All Transfers")
    }

    func testSelectedTargetPersistsAcrossDirectionChanges() {
        var state = TransferNavigationState(selectedTargetID: "devbox")

        state.transferMode = .pull
        state.transferMode = .drop

        XCTAssertEqual(state.selectedTargetID, "devbox")
    }

    func testClearsSelectedTargetWhenItIsNoLongerAvailable() {
        var state = TransferNavigationState(selectedTargetID: "devbox")
        let targets = [
            SSHTarget(name: "gpu-box", source: .config)
        ]

        state.reconcileSelectedTarget(with: targets)

        XCTAssertNil(state.selectedTargetID)
    }

    func testRefreshingTargetsDoesNotAutoSelectFirstTarget() {
        var state = TransferNavigationState()
        let targets = [
            SSHTarget(name: "devbox", source: .config),
            SSHTarget(name: "gpu-box", source: .config)
        ]

        state.reconcileTargets(targets)

        XCTAssertNil(state.selectedTargetID)
    }
}
