import Foundation

public struct TargetResolver {
    public init() {}

    public static func merge(active: [SSHTarget], configured: [SSHTarget]) -> [SSHTarget] {
        var seen = Set<String>()
        var result: [SSHTarget] = []

        for target in active {
            if seen.insert(target.connectName).inserted {
                result.append(target)
            }
        }

        for target in configured {
            if seen.insert(target.connectName).inserted {
                result.append(target)
            }
        }

        return result
    }
}
