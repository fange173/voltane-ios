import Foundation

/// 请求入口：Bearer 令牌、主备地址切换、401 后刷新一次令牌再重试。
public actor APIClient {
    public static let apiVersion = 1
    private let transport: Transport
    private let tokens: TokenStore
    private var server: ServerConfig
    private var refreshTask: Task<Bool, Never>?
    private var onUnauthorized: (@Sendable () -> Void)?
    private var onServerChange: (@Sendable (ServerConfig) -> Void)?
    /// 刷新令牌的最短间隔，启动时超过这个间隔就刷新一次。
    public static let refreshInterval: TimeInterval = 7 * 24 * 3600

    public init(server: ServerConfig, tokens: TokenStore, transport: Transport = URLSessionTransport()) {
        self.server = server; self.tokens = tokens; self.transport = transport
    }

    public func setHandlers(onUnauthorized: (@Sendable () -> Void)?, onServerChange: (@Sendable (ServerConfig) -> Void)?) {
        self.onUnauthorized = onUnauthorized; self.onServerChange = onServerChange
    }

    public func setServer(_ s: ServerConfig) { server = s }
    public var currentServer: ServerConfig { server }

    public func send<R: Decodable & Sendable>(_ endpoint: Endpoint<R>) async throws -> R {
        let data = try await sendRaw(endpoint)
        do {
            return try JSONCoding.decoder.decode(R.self, from: data)
        } catch {
            throw APIError(status: -1, detail: .text("服务端返回的数据格式不符，请检查 App 与服务端是否是匹配的版本"))
        }
    }

    public func sendRaw<R>(_ endpoint: Endpoint<R>) async throws -> Data {
        do {
            return try await perform(endpoint)
        } catch let e as APIError where e.status == 401 && endpoint.authenticated && endpoint.path != "/api/auth/refresh" {
            if await refreshToken() { return try await perform(endpoint) }
            tokens.clear()
            onUnauthorized?()
            throw e
        }
    }

    /// 启动时调用：距上次刷新超过 7 天就换发新令牌，90 天内打开过 App 就一直保持登录。
    public func refreshIfNeeded(now: Date = Date()) async {
        guard let t = tokens.load(), now.timeIntervalSince(t.refreshedAt) > Self.refreshInterval else { return }
        _ = await refreshToken()
    }

    private func refreshToken() async -> Bool {
        if let task = refreshTask { return await task.value }
        let task = Task { [self] () -> Bool in
            do {
                let data = try await perform(API.refresh())
                let r = try JSONCoding.decoder.decode(TokenResponse.self, from: data)
                try tokens.save(StoredToken(token: r.token, expiresAt: r.expiresAt.date))
                return true
            } catch {
                return false
            }
        }
        refreshTask = task
        let ok = await task.value
        refreshTask = nil
        return ok
    }

    private func perform<R>(_ endpoint: Endpoint<R>) async throws -> Data {
        let candidates = server.candidates
        var lastError: APIError = .network()
        for (index, base) in candidates.enumerated() {
            let request = try makeRequest(endpoint, base: base, quickTimeout: candidates.count > 1 && index == 0)
            do {
                let (data, response) = try await transport.send(request)
                if base != server.lastGood {
                    server.lastGood = base
                    onServerChange?(server)
                }
                guard (200..<300).contains(response.statusCode) else { throw APIError.parse(status: response.statusCode, data: data) }
                return data
            } catch let e as APIError {
                throw e
            } catch let e as URLError where e.isConnectivity {
                lastError = .network(e.code == .timedOut ? "连接超时" : "网络连接失败")
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = .network()
            }
        }
        throw lastError
    }

    private func makeRequest<R>(_ ep: Endpoint<R>, base: URL, quickTimeout: Bool) throws -> URLRequest {
        guard var comps = URLComponents(url: base.appendingPathComponent(ep.path), resolvingAgainstBaseURL: false) else {
            throw APIError.network("服务器地址不正确")
        }
        if !ep.query.isEmpty { comps.queryItems = ep.query }
        guard let url = comps.url else { throw APIError.network("服务器地址不正确") }
        var req = URLRequest(url: url, timeoutInterval: quickTimeout ? 3 : 30)
        req.httpMethod = ep.method.rawValue
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = ep.body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if ep.authenticated, let t = tokens.load() { req.setValue("Bearer \(t.token)", forHTTPHeaderField: "Authorization") }
        return req
    }
}
