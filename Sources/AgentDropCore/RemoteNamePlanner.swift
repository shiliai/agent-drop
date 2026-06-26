public struct RemoteNamePlanner {
    private let planner: NamePlanner

    public init(originalName: String) {
        self.planner = NamePlanner(originalName: originalName)
    }

    public func candidates(prefixCount: Int = 100) -> AnySequence<String> {
        planner.candidates(prefixCount: prefixCount)
    }
}
