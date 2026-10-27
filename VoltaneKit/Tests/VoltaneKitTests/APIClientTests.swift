import Foundation
import Testing
@testable import VoltaneKit

/// 按脚本返回响应的假网络层，同时记录收到的请求。
final class FakeTransport: Transport, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest, Int) throws -> (Int, Data)
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    private let handler: Handler

    init(_ handler: @escaping Handler) { self.handler = handler }

    var received: [URLRequest] { lock.withLock { requests } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let n = lock.withLock { requests.append(request); return requests.count }
        let (status, data) = try handler(request, n)
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

private func json(_ s: String) -> Data { Data(s.utf8) }

private func server(_ primary: String = "http://a.local:8000", backup: String? = nil) -> ServerConfig {
    ServerConfig(primary: URL(string: primary)!, backup: backup.flatMap(URL.init(string:)))
}

@Suite struct APIClientTests {
    @Test func sendsBearerHeaderOnlyForAuthenticatedEndpoints() async throws {
        let t = FakeTransport { _, _ in (200, json(#"{"ok":true,"service":"voltane","version":"0.1.0","api_version":1}"#)) }
        let store = MemoryTokenStore(StoredToken(token: "tok-123", expiresAt: .distantFuture))
        let c = APIClient(server: server(), tokens: store, transport: t)
        _ = try await c.send(API.health())
        #expect(t.received[0].value(forHTTPHeaderField: "Authorization") == nil)
        _ = try? await c.send(API.me())
        #expect(t.received[1].value(forHTTPHeaderField: "Authorization") == "Bearer tok-123")
        #expect(t.received[1].url?.absoluteString == "http://a.local:8000/api/auth/me")
    }

    @Test func unauthorizedRefreshesOnceThenRetries() async throws {
        let t = FakeTransport { req, _ in
            let auth = req.value(forHTTPHeaderField: "Authorization")
            if req.url!.path == "/api/auth/refresh" { return (200, json(#"{"token":"new-tok","expires_at":"2027-01-01T00:00:00Z"}"#)) }
            if auth == "Bearer old-tok" { return (401, json(#"{"detail":"登录已失效，请重新登录"}"#)) }
            return (200, json(#"{"id":1,"username":"a","name":"A","color":"c","role":"admin","is_admin":true,"must_change_password":false,"settings":{}}"#))
        }
        let store = MemoryTokenStore(StoredToken(token: "old-tok", expiresAt: .distantFuture))
        let c = APIClient(server: server(), tokens: store, transport: t)
        let me = try await c.send(API.me())
        #expect(me.username == "a")
        #expect(store.load()?.token == "new-tok")
        #expect(t.received.map(\.url!.path) == ["/api/auth/me", "/api/auth/refresh", "/api/auth/me"])
    }

    @Test func refreshFailureClearsTokenAndNotifies() async {
        let t = FakeTransport { _, _ in (401, json(#"{"detail":"登录已失效，请重新登录"}"#)) }
        let store = MemoryTokenStore(StoredToken(token: "old", expiresAt: .distantFuture))
        let c = APIClient(server: server(), tokens: store, transport: t)
        let flag = Box<[String]>([])
        await c.setHandlers(onUnauthorized: { flag.append("out") }, onServerChange: nil)
        await #expect(throws: APIError.self) { try await c.send(API.me()) }
        #expect(store.load() == nil)
        #expect(flag.value == ["out"])
    }

    @Test func failsOverToBackupAndRemembersIt() async throws {
        let t = FakeTransport { req, _ in
            if req.url!.host == "a.local" { throw URLError(.timedOut) }
            return (200, json(#"{"ok":true,"service":"voltane","version":"0.1.0","api_version":1}"#))
        }
        let c = APIClient(server: server(backup: "https://b.example.com"), tokens: MemoryTokenStore(), transport: t)
        let changed = Box<[String]>([])
        await c.setHandlers(onUnauthorized: nil, onServerChange: { changed.append($0.lastGood?.host ?? "") })
        _ = try await c.send(API.health())
        #expect(t.received.map(\.url!.host!) == ["a.local", "b.example.com"])
        #expect(t.received[0].timeoutInterval == 3)
        #expect(changed.value == ["b.example.com"])
        _ = try await c.send(API.health())
        #expect(t.received.map(\.url!.host!) == ["a.local", "b.example.com", "b.example.com"])
    }

    @Test func allUnreachableIsNetworkError() async {
        let t = FakeTransport { _, _ in throw URLError(.cannotConnectToHost) }
        let c = APIClient(server: server(backup: "http://b.local"), tokens: MemoryTokenStore(), transport: t)
        do { _ = try await c.send(API.health()); Issue.record("应抛错") } catch let e as APIError { #expect(e.isNetwork) } catch { Issue.record("类型不对") }
    }

    @Test func serverErrorsAreNotRetriedOnBackup() async {
        let t = FakeTransport { _, _ in (500, json("oops")) }
        let c = APIClient(server: server(backup: "http://b.local"), tokens: MemoryTokenStore(), transport: t)
        await #expect(throws: APIError.self) { try await c.send(API.health()) }
        #expect(t.received.count == 1)
    }

    @Test func refreshOnlyAfterSevenDays() async {
        let t = FakeTransport { _, _ in (200, json(#"{"token":"n","expires_at":"2027-01-01T00:00:00Z"}"#)) }
        let fresh = MemoryTokenStore(StoredToken(token: "t", expiresAt: .distantFuture, refreshedAt: Date()))
        let c = APIClient(server: server(), tokens: fresh, transport: t)
        await c.refreshIfNeeded()
        #expect(t.received.isEmpty)
        let stale = MemoryTokenStore(StoredToken(token: "t", expiresAt: .distantFuture, refreshedAt: Date().addingTimeInterval(-8 * 86400)))
        let c2 = APIClient(server: server(), tokens: stale, transport: t)
        await c2.refreshIfNeeded()
        #expect(t.received.count == 1 && stale.load()?.token == "n")
    }

    @Test func normalizesServerInput() {
        #expect(ServerConfig.normalize("192.168.1.5:8000/")?.absoluteString == "http://192.168.1.5:8000")
        #expect(ServerConfig.normalize("  https://car.example.com// ")?.absoluteString == "https://car.example.com")
        #expect(ServerConfig.normalize("") == nil)
        let remote = ServerConfig(primary: URL(string: "http://car.example.com")!)
        let lan = ServerConfig(primary: URL(string: "http://192.168.1.5:8000")!)
        let tls = ServerConfig(primary: URL(string: "https://car.example.com")!)
        #expect(remote.primaryIsInsecureRemote && !lan.primaryIsInsecureRemote && !tls.primaryIsInsecureRemote)
    }

    @Test func decodeFailureIsReadableNotCrash() async {
        let t = FakeTransport { _, _ in (200, json(#"{"unexpected":true}"#)) }
        let c = APIClient(server: server(), tokens: MemoryTokenStore(), transport: t)
        do { _ = try await c.send(API.health()); Issue.record("应抛错") } catch let e as APIError { #expect(e.status == -1 && e.message.contains("版本")) } catch {}
    }
}

@Suite struct CacheTests {
    @Test func scopedByServerAndUser() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("c-\(UUID().uuidString)")
        let cache = ResponseCache(directory: dir)
        await cache.setScope(server: URL(string: "http://x")!, userId: 1)
        await cache.write(Data("one".utf8), key: "/api/a")
        #expect(await cache.read("/api/a")?.data == Data("one".utf8))
        await cache.setScope(server: URL(string: "http://x")!, userId: 2)
        #expect(await cache.read("/api/a") == nil)
        await cache.setScope(server: URL(string: "http://x")!, userId: 1)
        await cache.clear()
        #expect(await cache.read("/api/a") == nil)
    }

    @Test func evictsLeastRecentlyUsedOverLimit() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("c-\(UUID().uuidString)")
        let cache = ResponseCache(directory: dir, limit: 3000)
        let blob = Data(repeating: 65, count: 1000)
        for i in 0..<5 { await cache.write(blob, key: "k\(i)", at: Date(timeIntervalSinceNow: Double(i - 10))) }
        #expect(await cache.totalSize <= 3000)
        #expect(await cache.read("k0") == nil)
        #expect(await cache.read("k4") != nil)
    }
}
