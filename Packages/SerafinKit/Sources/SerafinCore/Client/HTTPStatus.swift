/// Reads HTTP statuses out of the errors the Jellyfin SDK throws.
enum HTTPStatus {
    /// The status of a response outside 200...299, when `error` is the SDK's error for one.
    ///
    /// The SDK's transport, Get, throws `APIError.unacceptableStatusCode(Int)` for these. SerafinCore does not
    /// import Get, so it reads the case by reflection; the tests against a stubbed server fail if Get changes it.
    static func of(_ error: any Error) -> Int? {
        let mirror = Mirror(reflecting: error)
        guard
            mirror.displayStyle == .enum,
            let child = mirror.children.first,
            child.label == "unacceptableStatusCode"
        else { return nil }
        return child.value as? Int
    }
}
