import CryptoKit
import Foundation

/// 接口响应缓存：按「服务器 + 用户 ID + 路径和参数」存成文件，总大小上限 20MB，按最近使用淘汰。
public actor ResponseCache {
    public static let sizeLimit = 20 * 1024 * 1024
    private let directory: URL
    private let limit: Int
    private var scope = "anonymous"

    public init(directory: URL, limit: Int = ResponseCache.sizeLimit) {
        self.directory = directory; self.limit = limit
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// 换服务器或换账号后缓存互不可见。
    public func setScope(server: URL, userId: Int?) { scope = "\(server.absoluteString)|\(userId.map(String.init) ?? "-")" }
    public var currentScope: String { scope }

    private func file(_ key: String) -> URL {
        let digest = SHA256.hash(data: Data((scope + "|" + key).utf8))
        return directory.appendingPathComponent(digest.map { String(format: "%02x", $0) }.joined())
    }

    public func read(_ key: String) -> (data: Data, updatedAt: Date)? {
        let url = file(key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let date = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? Date()
        return (data, date)
    }

    public func write(_ data: Data, key: String, at date: Date = Date()) {
        let url = file(key)
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        evictIfNeeded()
    }

    /// 退出登录或换账号时清空。
    public func clear() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public var totalSize: Int { entries().reduce(0) { $0 + $1.size } }

    private func entries() -> [(url: URL, size: Int, date: Date)] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return urls.compactMap { u in
            guard let v = try? u.resourceValues(forKeys: Set(keys)) else { return nil }
            return (u, v.fileSize ?? 0, v.contentModificationDate ?? .distantPast)
        }
    }

    private func evictIfNeeded() {
        var list = entries()
        var total = list.reduce(0) { $0 + $1.size }
        guard total > limit else { return }
        list.sort { $0.date < $1.date }
        for e in list where total > limit {
            try? FileManager.default.removeItem(at: e.url)
            total -= e.size
        }
    }
}

public struct Loaded<Value: Sendable>: Sendable {
    public var value: Value
    public var updatedAt: Date
    public var isCached: Bool
}

/// 先显示缓存、再后台刷新（stale-while-revalidate）的数据入口。
public actor Repository {
    public let client: APIClient
    public let cache: ResponseCache

    public init(client: APIClient, cache: ResponseCache) { self.client = client; self.cache = cache }

    public func cached<R: Decodable & Sendable>(_ endpoint: Endpoint<R>) async -> Loaded<R>? {
        guard let hit = await cache.read(endpoint.cacheKeyPath), let v = try? JSONCoding.decoder.decode(R.self, from: hit.data) else { return nil }
        return Loaded(value: v, updatedAt: hit.updatedAt, isCached: true)
    }

    public func fetch<R: Decodable & Sendable>(_ endpoint: Endpoint<R>) async throws -> Loaded<R> {
        let data = try await client.sendRaw(endpoint)
        let v: R
        do { v = try JSONCoding.decoder.decode(R.self, from: data) } catch {
            throw APIError(status: -1, detail: .text("服务端返回的数据格式不符，请检查 App 与服务端是否是匹配的版本"))
        }
        await cache.write(data, key: endpoint.cacheKeyPath)
        return Loaded(value: v, updatedAt: Date(), isCached: false)
    }
}
