import Foundation

/// 服务器地址：主地址加可选的备用地址（例如局域网 http 与反代 https 各一个）。
public struct ServerConfig: Codable, Sendable, Equatable {
    public var primary: URL
    public var backup: URL?
    /// 最近一次可用的地址，下次请求优先使用。
    public var lastGood: URL?

    public init(primary: URL, backup: URL? = nil, lastGood: URL? = nil) {
        self.primary = primary; self.backup = backup; self.lastGood = lastGood
    }

    /// 自动补 `http://`、去掉末尾的 `/` 和多余空白；无法识别时返回 nil。
    public static func normalize(_ text: String) -> URL? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// 尝试顺序：最近可用的在前，另一个在后。
    public var candidates: [URL] {
        var list = [primary]
        if let backup { list.append(backup) }
        if let lastGood, let i = list.firstIndex(of: lastGood), i > 0 { list.swapAt(0, i) }
        return list
    }

    /// 主地址是 http 且不是局域网地址：明文传输，建议改用 https。
    public var primaryIsInsecureRemote: Bool {
        guard primary.scheme?.lowercased() == "http", let host = primary.host?.lowercased() else { return false }
        return !Self.isLocalHost(host)
    }

    static func isLocalHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".lan") || host.hasSuffix(".localhost") { return true }
        let p = host.split(separator: ".").compactMap { Int($0) }
        guard p.count == 4 else { return !host.contains(".") }
        return p[0] == 10 || p[0] == 127 || (p[0] == 192 && p[1] == 168) || (p[0] == 172 && (16...31).contains(p[1])) || (p[0] == 169 && p[1] == 254)
    }
}
