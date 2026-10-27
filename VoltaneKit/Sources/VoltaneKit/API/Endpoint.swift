import Foundation

public enum HTTPMethod: String, Sendable { case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE" }

/// 一个接口调用：方法、路径、查询参数和 JSON 请求体。
public struct Endpoint<Response: Decodable & Sendable>: Sendable {
    public var method: HTTPMethod
    public var path: String
    public var query: [URLQueryItem]
    public var body: Data?
    public var authenticated: Bool

    public init(_ method: HTTPMethod = .get, _ path: String, query: [URLQueryItem] = [], body: Data? = nil, authenticated: Bool = true) {
        self.method = method; self.path = path; self.query = query; self.body = body; self.authenticated = authenticated
    }

    public init<Body: Encodable>(_ method: HTTPMethod, _ path: String, json: Body, query: [URLQueryItem] = [], authenticated: Bool = true) throws {
        self.init(method, path, query: query, body: try JSONCoding.encoder.encode(json), authenticated: authenticated)
    }

    /// 缓存键里使用的路径加查询串。
    public var cacheKeyPath: String {
        guard !query.isEmpty else { return path }
        let q = query.sorted { $0.name < $1.name }.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
        return path + "?" + q
    }
}

public extension URLQueryItem {
    init(_ name: String, _ value: Int) { self.init(name: name, value: String(value)) }
    init(_ name: String, _ value: String) { self.init(name: name, value: value) }
    init(_ name: String, _ value: Bool) { self.init(name: name, value: value ? "true" : "false") }
}
