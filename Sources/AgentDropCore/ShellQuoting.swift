public enum ShellQuoting {
    public static func singleQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    public static func homeRelativeCommandPath(_ relativePath: String) -> String {
        "$HOME/" + singleQuote(relativePath)
    }
}
