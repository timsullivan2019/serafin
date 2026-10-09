import Foundation

/// A server address as the user typed it, turned into a URL Serafin can connect to.
public struct ServerAddress: Hashable, Sendable {
    /// Jellyfin's default HTTP port.
    public static let jellyfinHTTPPort = 8096
    /// Jellyfin's default HTTPS port.
    public static let jellyfinHTTPSPort = 8920

    /// The address to try first.
    public let url: URL
    /// The address to try once if ``url`` cannot be reached: Jellyfin's default port for the same scheme, when the
    /// user typed no port and the first attempt did not already use it, or plain HTTP on Jellyfin's port for a
    /// Tailscale name typed without a scheme or port, when it has no HTTPS.
    public let fallback: URL?

    /// Parses an address such as `jellyfin.example.com`, `192.168.1.20:8096` or `https://example.com/jellyfin`.
    ///
    /// Without a scheme, a public host gets `https` on its standard port, since most self-hosters sit behind a
    /// reverse proxy, and a private host gets `http` on 8096. A Tailscale name without a port, such as
    /// `nas.tailnet-1234.ts.net`, gets `https` first, since Tailscale can give it a certificate, and `http` on 8096
    /// after. Anything but `http` and `https` is refused, as are addresses with credentials, a query or a fragment.
    ///
    /// - Throws: ``SerafinError/invalidAddress`` when the text is not a usable address.
    public static func parse(_ input: String) throws -> ServerAddress {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { throw SerafinError.invalidAddress }

        var scheme: String?
        var rest = text
        if let separator = text.range(of: "://") {
            let typed = text[..<separator.lowerBound].lowercased()
            guard typed == "http" || typed == "https" else { throw SerafinError.invalidAddress }
            scheme = typed
            rest = String(text[separator.upperBound...])
        }
        // A bare IPv6 address has several colons and no brackets; bracket it so the colons are not read as a port.
        if !rest.hasPrefix("["), !rest.contains("/"), rest.filter({ $0 == ":" }).count >= 2 {
            rest = "[\(rest)]"
        }

        guard
            var components = URLComponents(string: "placeholder://\(rest)"),
            let host = components.host, !host.isEmpty,
            components.user == nil, components.password == nil,
            components.query == nil, components.fragment == nil
        else { throw SerafinError.invalidAddress }

        let typedPort = components.port
        // A Tailscale name typed without a scheme or port is treated like a public host until HTTPS fails.
        let isTailscaleNameAlone = scheme == nil && typedPort == nil && PrivateNetwork.isTailscaleName(host)
        let prefersHTTP = PrivateNetwork.isPrivate(host: host) && !isTailscaleNameAlone
        let resolvedScheme = scheme ?? defaultScheme(port: typedPort, prefersHTTP: prefersHTTP)
        components.scheme = resolvedScheme
        components.host = host.lowercased()
        if scheme == nil, typedPort == nil, prefersHTTP {
            components.port = jellyfinHTTPPort
        }
        while components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        guard let url = components.url else { throw SerafinError.invalidAddress }

        var fallback: URL?
        if isTailscaleNameAlone {
            components.scheme = "http"
            components.port = jellyfinHTTPPort
            fallback = components.url
        } else if typedPort == nil {
            let defaultPort = resolvedScheme == "https" ? jellyfinHTTPSPort : jellyfinHTTPPort
            if components.port != defaultPort {
                components.port = defaultPort
                fallback = components.url
            }
        }
        return ServerAddress(url: url, fallback: fallback)
    }

    private static func defaultScheme(port: Int?, prefersHTTP: Bool) -> String {
        switch port {
        case 443, jellyfinHTTPSPort: "https"
        case 80, jellyfinHTTPPort: "http"
        default: prefersHTTP ? "http" : "https"
        }
    }
}
