import Foundation

public enum AgentDropRoute: Equatable {
    case pull

    public static let scheme = "agentdrop"
    public static let pullURL = URL(string: "\(scheme)://pull")!

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else {
            return nil
        }

        let routeName = url.host ?? url.pathComponents.first { $0 != "/" }
        switch routeName?.lowercased() {
        case "pull":
            self = .pull
        default:
            return nil
        }
    }
}
