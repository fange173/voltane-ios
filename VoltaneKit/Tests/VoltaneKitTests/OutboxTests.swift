import Foundation
import Testing
@testable import VoltaneKit

private func tempDir() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("voltane-test-\(UUID().uuidString)")
}

private func body(_ clientId: String) -> Data {
    try! JSONEncoder().encode(["client_id": clientId, "kind": "fuel"])
}

@Suite struct OutboxTests {
    @Test func persistsAcrossInstances() async {
        let dir = tempDir()
        let a = Outbox(directory: dir)
        await a.setScope(server: URL(string: "http://x")!, userId: 1)
        await a.enqueue(kind: .record, vehicleId: 7, label: "加油", body: body("c1"))
        let b = Outbox(directory: dir)
        await b.setScope(server: URL(string: "http://x")!, userId: 1)
        #expect(await b.items().count == 1)
        #expect(await b.items(vehicleId: 8).isEmpty)
    }

    @Test func isolatedByAccount() async {
        let dir = tempDir()
        let o = Outbox(directory: dir)
        await o.setScope(server: URL(string: "http://x")!, userId: 1)
        await o.enqueue(kind: .record, vehicleId: 1, label: "加油", body: body("c1"))
        await o.setScope(server: URL(string: "http://x")!, userId: 2)
        #expect(await o.items().isEmpty)
        await o.setScope(server: URL(string: "http://x")!, userId: 1)
        #expect(await o.items().count == 1)
    }

    @Test func flushKeepsOnNetworkResendsSameClientId() async throws {
        let o = Outbox(directory: tempDir())
        await o.enqueue(kind: .record, vehicleId: 1, label: "加油", body: body("same-id"))
        let seen = Box<[String]>([])
        let offline = await o.flush { item in
            seen.append(String(data: item.body, encoding: .utf8)!)
            throw APIError.network()
        }
        #expect(offline.sent == 0 && offline.remaining == 1)
        let online = await o.flush { item in seen.append(String(data: item.body, encoding: .utf8)!) }
        #expect(online.sent == 1 && online.remaining == 0)
        let values = seen.value
        #expect(values.count == 2 && values[0] == values[1] && values[0].contains("same-id"))
    }

    @Test func flushRulesPerStatus() async {
        let o = Outbox(directory: tempDir())
        for i in 0..<5 { await o.enqueue(kind: .expense, vehicleId: 1, label: "费用\(i)", body: body("c\(i)")) }
        let report = await o.flush { item in
            switch item.label {
            case "费用0": return
            case "费用1": throw APIError(status: 500, detail: .text("boom"))
            case "费用2": throw APIError(status: 409, detail: .coded(code: "duplicate", message: "重复", payload: .null))
            case "费用3": throw APIError(status: 422, detail: .validation(["金额不对"]))
            default: throw APIError(status: 404, detail: .text("车辆不存在"))
            }
        }
        #expect(report.sent == 2)
        #expect(report.dropped.count == 2 && report.dropped[0].contains("金额不对"))
        #expect(report.remaining == 1)
        #expect(await o.items().map(\.label) == ["费用1"])
    }

    @Test func unauthorizedKeepsEverythingForAfterRelogin() async {
        let o = Outbox(directory: tempDir())
        for i in 0..<3 { await o.enqueue(kind: .record, vehicleId: 1, label: "r\(i)", body: body("c\(i)")) }
        let report = await o.flush { _ in throw APIError(status: 401, detail: .text("未登录")) }
        #expect(report.dropped.isEmpty && report.remaining == 3)
    }

    @Test func editPendingKeepsClientId() async {
        let o = Outbox(directory: tempDir())
        let item = await o.enqueue(kind: .record, vehicleId: 1, label: "加油", body: body("keep-me"))
        await o.replace(item.id, label: "加油（改）", body: body("keep-me"))
        let got = await o.items()
        #expect(got.count == 1 && got[0].label == "加油（改）")
        await o.remove(item.id)
        #expect(await o.items().isEmpty)
    }
}

final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var v: T
    init(_ v: T) { self.v = v }
    var value: T { lock.withLock { v } }
    func set(_ x: T) { lock.withLock { v = x } }
}

extension Box where T == [String] {
    func append(_ s: String) { lock.withLock { v.append(s) } }
}
