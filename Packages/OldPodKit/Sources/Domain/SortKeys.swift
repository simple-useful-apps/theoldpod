/// Shared string helpers used to compute classic sort orders across modules.
public enum SortKeys {
    /// Strips a leading "The " (case-insensitive) for artist sorting, e.g.
    /// "The Beatles" sorts under "Beatles". Empty-safe.
    public static func articleStripped(_ s: String) -> String {
        guard s.lowercased().hasPrefix("the ") else { return s }
        return String(s.dropFirst(4))
    }
}
