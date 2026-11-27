import Foundation

/// The part of an HTTP(S) address that website rules match.
struct WebsiteAddress: Equatable {
    private static let unreserved = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8)

    let host: String
    let entry: String
    private let segments: [String]

    var isDomainOnly: Bool { segments.isEmpty }

    /// Equal for two addresses exactly when `==` is, so imports can de-duplicate with a set.
    var matchKey: String { ([host] + segments).joined(separator: "/") }

    init?(entry: String) {
        let entry = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entry.isEmpty, entry.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        let hasScheme = entry.range(of: "://").map { separator in
            !entry[..<separator.lowerBound].contains { "/?#".contains($0) }
        } ?? false
        guard let url = URL(string: hasScheme ? entry : "https://\(entry)"),
              url.user() == nil, url.password() == nil else { return nil }
        self.init(url: url)
    }

    init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var enteredHost = url.host()?.lowercased(),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        if enteredHost.hasSuffix(".") { enteredHost.removeLast() }
        let host = enteredHost.hasPrefix("www.") ? String(enteredHost.dropFirst(4)) : enteredHost
        guard !host.isEmpty, !host.hasSuffix("."),
              !host.contains(where: { "/?#@".contains($0) }),
              host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        self.host = host

        var path = components.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        // Only literal slashes form boundaries. Preserve case and escapes for reserved characters.
        let parts = path.isEmpty ? [] : path.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        segments = parts.map(Self.normalizedSegment)
        entry = enteredHost + path
    }

    func matches(_ address: WebsiteAddress) -> Bool {
        if isDomainOnly {
            return address.host == host || address.host.hasSuffix("." + host)
        }
        return address.host == host && address.segments.starts(with: segments)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.host == rhs.host && lhs.segments == rhs.segments
    }

    private static func normalizedSegment(_ segment: Substring) -> String {
        guard segment.contains("%") else { return String(segment) }
        let bytes = Array(segment.utf8)
        var result: [UInt8] = []
        var index = 0
        while index < bytes.count {
            guard bytes[index] == 0x25, index + 2 < bytes.count else {
                result.append(bytes[index])
                index += 1
                continue
            }
            let hex = String(decoding: bytes[(index + 1)...(index + 2)], as: UTF8.self)
            if let byte = UInt8(hex, radix: 16), unreserved.contains(byte) {
                result.append(byte)
            } else {
                result.append(0x25)
                result.append(contentsOf: hex.uppercased().utf8)
            }
            index += 3
        }
        return String(decoding: result, as: UTF8.self)
    }
}
