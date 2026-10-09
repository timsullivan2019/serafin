import Network

/// Decides whether a host is on the user's own network, where Serafin allows plain HTTP after a warning.
///
/// Tailscale counts as the user's own network: its addresses (100.64.0.0/10, and IPv6 inside fc00::/7) and its
/// MagicDNS names (`.ts.net`) reach the server through the user's tailnet, where WireGuard encrypts everything. iOS
/// lets plain HTTP through to them only because Serafin's Info.plist lists 100.64.0.0/10 and `ts.net` as App
/// Transport Security exceptions.
public enum PrivateNetwork {
    /// Whether `host` is private: an RFC 1918, loopback, link-local or shared (100.64.0.0/10) IPv4 address, a
    /// loopback, link-local or unique-local IPv6 address, `localhost`, a `.local` name, a Tailscale `.ts.net` name,
    /// or a bare name without a dot.
    ///
    /// Only the name is judged; nothing is resolved. A public-looking name that happens to point at a home server
    /// counts as public.
    public static func isPrivate(host: String) -> Bool {
        guard let name = normalized(host) else { return false }

        if name == "localhost" || name.hasSuffix(".localhost") || name.hasSuffix(".local") || isTailscale(name) {
            return true
        }
        if let address = IPv4Address(name) {
            return isPrivate(address.rawValue)
        }
        let withoutZone = name.split(separator: "%", maxSplits: 1).first.map(String.init) ?? name
        if let address = IPv6Address(withoutZone) {
            return isPrivate(ipv6: address.rawValue)
        }
        return !name.contains(".") && !name.contains(":")
    }

    /// Whether `host` is a Tailscale MagicDNS name, such as `nas.tailnet-1234.ts.net`. Tailscale can give these names
    /// real certificates, so Serafin tries HTTPS on them before plain HTTP.
    public static func isTailscaleName(_ host: String) -> Bool {
        normalized(host).map(isTailscale) ?? false
    }

    private static func isTailscale(_ name: String) -> Bool {
        name.hasSuffix(".ts.net")
    }

    /// `host` in lowercase without IPv6 brackets or a trailing dot, or nil when nothing is left.
    private static func normalized(_ host: String) -> String? {
        var name = host.lowercased()
        if name.hasPrefix("["), name.hasSuffix("]") {
            name = String(name.dropFirst().dropLast())
        }
        if name.hasSuffix(".") {
            name.removeLast()
        }
        return name.isEmpty ? nil : name
    }

    private static func isPrivate(_ v4: some Collection<UInt8>) -> Bool {
        let bytes = Array(v4)
        guard bytes.count == 4 else { return false }
        switch (bytes[0], bytes[1]) {
        case (10, _), (127, _): return true
        case (172, 16...31): return true
        case (192, 168): return true
        case (169, 254): return true
        // Shared address space, where Tailscale gives each device its address.
        case (100, 64...127): return true
        default: return false
        }
    }

    private static func isPrivate(ipv6 raw: some Collection<UInt8>) -> Bool {
        let bytes = Array(raw)
        guard bytes.count == 16 else { return false }
        let isLoopback = bytes[0..<15].allSatisfy { $0 == 0 } && bytes[15] == 1
        let isLinkLocal = bytes[0] == 0xFE && bytes[1] & 0xC0 == 0x80
        let isUniqueLocal = bytes[0] & 0xFE == 0xFC
        let isMappedIPv4 = bytes[0..<10].allSatisfy { $0 == 0 } && bytes[10] == 0xFF && bytes[11] == 0xFF
        if isMappedIPv4 {
            return isPrivate(bytes[12..<16])
        }
        return isLoopback || isLinkLocal || isUniqueLocal
    }
}
