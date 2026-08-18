import Foundation

/// Persistent settings for the proxy, mirroring the Python `ProxyConfig`.
struct ProxySettings: Codable, Equatable {
    var host: String = "127.0.0.1"
    var port: UInt16 = 1443
    var secret: String
    var fakeTLSDomain: String = ""
    var fallbackCFProxy: Bool = true
    var proxyProtocol: Bool = false
    var forceTestDC: Bool = false
    var dcRedirects: [String: String] = [
        "2": "149.154.167.220",
        "4": "149.154.167.220",
    ]

    init() {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            secret = bytes.map { String(format: "%02x", $0) }.joined()
        } else {
            secret = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(32).lowercased()
        }
    }

    // MARK: - Persistence

    private static let defaultsKey = "proxy_settings_v1"

    static func load() -> ProxySettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(ProxySettings.self, from: data)
        else {
            return ProxySettings()
        }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: ProxySettings.defaultsKey)
    }

    // MARK: - Derived helpers

    /// Builds the `tg://` link for standard (dd) secret.
    var ddLink: String {
        "tg://proxy?server=\(host)&port=\(port)&secret=dd\(secret)"
    }

    /// Builds the `tg://` link for fake-TLS (ee) secret.
    var eeLink: String? {
        guard !fakeTLSDomain.isEmpty else { return nil }
        let domainHex = fakeTLSDomain
            .data(using: .utf8)?
            .map { String(format: "%02x", $0) }
            .joined() ?? ""
        return "tg://proxy?server=\(host)&port=\(port)&secret=ee\(secret)\(domainHex)"
    }

    var secretBytes: Data? {
        var data = Data()
        var index = secret.startIndex
        while index < secret.endIndex {
            let end = secret.index(index, offsetBy: 2, limitedBy: secret.endIndex) ?? secret.endIndex
            let byteString = String(secret[index..<end])
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            index = end
        }
        return data
    }
}