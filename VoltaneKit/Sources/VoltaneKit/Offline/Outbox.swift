import CryptoKit
import Foundation

public struct OutboxItem: Codable, Sendable, Identifiable, Equatable {
    public enum Kind: String, Codable, Sendable { case record, expense }
    public let id: UUID
    public var kind: Kind
    public var vehicleId: Int
    public var label: String
    /// 提交体的原始 JSON，里面带着新建时生成的 client_id，重发时原样复用。
    public var body: Data
    public let queuedAt: Date

    public var path: String { kind == .record ? "/api/records" : "/api/expenses" }
}

public struct FlushReport: Sendable, Equatable {
    public var sent = 0
    public var dropped: [String] = []
    public var remaining = 0
}

/// 离线发件箱：只有新建记录和新建费用会进来，联网后按 client_id 幂等重发。
public actor Outbox {
    private let directory: URL
    private var scope = "anonymous"
    private var flushing = false

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// 发件箱按服务器与用户隔离，换账号不会看到也不会发送别人的待同步记录。
    public func setScope(server: URL, userId: Int) { scope = "\(server.absoluteString)|\(userId)" }

    private var fileURL: URL {
        let digest = SHA256.hash(data: Data(scope.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("outbox-\(digest).json")
    }

    private func load() -> [OutboxItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([OutboxItem].self, from: data)) ?? []
    }

    private func save(_ items: [OutboxItem]) {
        if items.isEmpty { try? FileManager.default.removeItem(at: fileURL); return }
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: fileURL, options: .atomic) }
    }

    public func items(vehicleId: Int? = nil) -> [OutboxItem] {
        load().filter { vehicleId == nil || $0.vehicleId == vehicleId }
    }

    public var count: Int { load().count }

    @discardableResult
    public func enqueue(kind: OutboxItem.Kind, vehicleId: Int, label: String, body: Data, now: Date = Date()) -> OutboxItem {
        let item = OutboxItem(id: UUID(), kind: kind, vehicleId: vehicleId, label: label, body: body, queuedAt: now)
        save(load() + [item])
        return item
    }

    public func remove(_ id: UUID) { save(load().filter { $0.id != id }) }

    /// 编辑待同步的条目，保留原 client_id。
    public func replace(_ id: UUID, label: String, body: Data) {
        save(load().map { var i = $0; if i.id == id { i.label = label; i.body = body }; return i })
    }

    /// 逐条重发。网络不通、登录失效或服务端 5xx 保留重试；重复（409 duplicate）视为已同步；其余 4xx 丢弃并提示，避免永远卡住。
    public func flush(send: @Sendable (OutboxItem) async throws -> Void) async -> FlushReport {
        guard !flushing else { return FlushReport(remaining: load().count) }
        flushing = true
        defer { flushing = false }
        var report = FlushReport()
        var left: [OutboxItem] = []
        let queue = load()
        for (i, item) in queue.enumerated() {
            do {
                try await send(item)
                report.sent += 1
            } catch let e as APIError {
                if e.isNetwork || e.isUnauthorized {
                    left.append(contentsOf: queue[i...])
                    break
                } else if e.status >= 500 {
                    left.append(item)
                } else if e.status == 409 && e.code == "duplicate" {
                    report.sent += 1
                } else {
                    report.dropped.append("一条离线记录同步失败：\(e.message)")
                }
            } catch {
                left.append(item)
            }
        }
        // 同步期间可能又有新条目入队
        let added = load().filter { cur in !queue.contains { $0.id == cur.id } }
        save(left + added)
        report.remaining = left.count + added.count
        return report
    }
}
