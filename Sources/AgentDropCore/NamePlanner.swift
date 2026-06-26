public struct NamePlanner {
    private let originalName: String

    public init(originalName: String) {
        self.originalName = originalName
    }

    public func candidates(prefixCount: Int = 100) -> AnySequence<String> {
        AnySequence {
            var index = 1
            return AnyIterator<String> {
                guard index <= prefixCount else { return nil }
                defer { index += 1 }
                return name(for: index)
            }
        }
    }

    private func name(for index: Int) -> String {
        guard index > 1 else { return originalName }

        let split = splitName(originalName)
        return split.base + "-\(index)" + split.extensionSuffix
    }

    private func splitName(_ name: String) -> (base: String, extensionSuffix: String) {
        if name.hasPrefix("."), name.dropFirst().contains(".") == false {
            return (name, "")
        }

        guard let dotIndex = name.lastIndex(of: "."), dotIndex != name.startIndex else {
            return (name, "")
        }

        let base = String(name[..<dotIndex])
        let suffix = String(name[dotIndex...])
        return (base, suffix)
    }
}

public struct LocalNamePlanner {
    private let planner: NamePlanner

    public init(originalName: String) {
        self.planner = NamePlanner(originalName: originalName)
    }

    public func candidates(prefixCount: Int = 100) -> AnySequence<String> {
        planner.candidates(prefixCount: prefixCount)
    }
}
