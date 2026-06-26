public enum PullFormPrefill {
    public struct Result: Equatable {
        public let selectedTargetID: SSHTarget.ID?
        public let pathText: String

        public init(selectedTargetID: SSHTarget.ID?, pathText: String) {
            self.selectedTargetID = selectedTargetID
            self.pathText = pathText
        }
    }

    public static func evaluate(clipboardText: String?, targets: [SSHTarget]) -> Result? {
        guard let clipboardText else { return nil }

        let normalizedInput = normalizedLines(from: clipboardText).joined(separator: "\n")
        guard !normalizedInput.isEmpty else { return nil }
        guard let paths = try? RemotePathParser.parse(normalizedInput) else { return nil }

        let matchedTargetIDs = paths.compactMap { path in
            path.hostHint.flatMap { matchingTargetID(for: $0, targets: targets) }
        }
        let hintedTargets = Set(matchedTargetIDs)
        let hintCount = paths.compactMap(\.hostHint).count

        if hintCount > 0, hintedTargets.count == 1, matchedTargetIDs.count == hintCount {
            return Result(
                selectedTargetID: hintedTargets.first,
                pathText: paths.map(\.path).joined(separator: "\n")
            )
        }

        return Result(selectedTargetID: nil, pathText: normalizedInput)
    }

    private static func matchingTargetID(for hostHint: String, targets: [SSHTarget]) -> SSHTarget.ID? {
        targets.first { target in
            target.name == hostHint || target.connectName == hostHint
        }?.id
    }

    private static func normalizedLines(from text: String) -> [String] {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
