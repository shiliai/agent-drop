import Foundation

public enum AppSection: String, Equatable, Sendable {
    case transfer
    case history

    public var contextColumnTitle: String {
        switch self {
        case .transfer:
            return "Hosts"
        case .history:
            return "Recent Transfers"
        }
    }
}

public enum TransferMode: String, Equatable, Sendable {
    case drop
    case pull
}

public struct TransferNavigationState: Equatable, Sendable {
    public var selectedSection: AppSection
    public var transferMode: TransferMode
    public var selectedTargetID: SSHTarget.ID?

    public init(
        selectedSection: AppSection = .transfer,
        transferMode: TransferMode = .drop,
        selectedTargetID: SSHTarget.ID? = nil
    ) {
        self.selectedSection = selectedSection
        self.transferMode = transferMode
        self.selectedTargetID = selectedTargetID
    }

    public mutating func apply(_ route: AgentDropRoute?) {
        switch route {
        case .pull:
            selectedSection = .transfer
            transferMode = .pull
        case nil:
            break
        }
    }

    public mutating func reconcileSelectedTarget(with targets: [SSHTarget]) {
        guard let selectedTargetID else { return }
        if !targets.contains(where: { $0.id == selectedTargetID }) {
            self.selectedTargetID = nil
        }
    }

    public mutating func reconcileTargets(_ targets: [SSHTarget]) {
        reconcileSelectedTarget(with: targets)
    }
}
