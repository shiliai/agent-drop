public enum FinderMenuTargetResolver {
    public static func connectName(representedObject: String?, title: String) -> String? {
        if let representedObject, !representedObject.isEmpty {
            return representedObject
        }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map(String.init)
        return parts.first
    }
}
