import Foundation

/// Answers kept for a short time, so going back to a screen does not ask the server again.
struct ResponseCache {
    /// The most answers kept. Beyond this, the ones closest to expiring go first.
    static let capacity = 200

    private struct Entry {
        let expires: ContinuousClock.Instant
        let value: any Sendable
    }

    private let lifetime: Duration
    private var entries: [String: Entry] = [:]

    /// Creates a cache that keeps each answer for `lifetime`.
    init(lifetime: Duration) {
        self.lifetime = lifetime
    }

    /// The answer saved under `key`, if it has not expired.
    func value<Value: Sendable>(for key: String) -> Value? {
        guard let entry = entries[key], entry.expires > .now else { return nil }
        return entry.value as? Value
    }

    /// Saves an answer under `key`.
    mutating func store(_ value: some Sendable, for key: String) {
        guard lifetime > .zero else { return }
        let now = ContinuousClock.now
        entries = entries.filter { $0.value.expires > now }
        if entries.count >= Self.capacity, let soonest = entries.min(by: { $0.value.expires < $1.value.expires }) {
            entries[soonest.key] = nil
        }
        entries[key] = Entry(expires: now.advanced(by: lifetime), value: value)
    }

    /// Forgets every answer.
    mutating func removeAll() {
        entries.removeAll()
    }

    /// The key for a request: its path and query, which together say exactly what was asked.
    static func key(_ url: URL?, _ query: [(String, String?)]?) -> String {
        let items = (query ?? []).map { "\($0)=\($1 ?? "")" }.joined(separator: "&")
        return "\(url?.absoluteString ?? "")?\(items)"
    }
}
