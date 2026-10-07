/// Jellyfin's item IDs.
public enum ItemID {
    /// Whether `id` is the kind of ID Jellyfin issues: letters, digits and dashes, nothing that could change a
    /// request's path. IDs from outside the app, such as a shortcut's or a Spotlight result's, are checked with this.
    public static func isPlain(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
}
