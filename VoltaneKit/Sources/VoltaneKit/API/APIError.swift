import Foundation

/// 服务端错误响应的 `detail` 有三种形态：字符串、`{code, message}` 对象、422 的校验数组。
public struct APIError: Error, LocalizedError, Sendable {
    public enum Detail: Sendable, Hashable {
        case text(String)
        case coded(code: String, message: String, payload: JSONValue)
        case validation([String])
    }

    public let status: Int
    public let detail: Detail

    public init(status: Int, detail: Detail) { self.status = status; self.detail = detail }

    /// 网络不通、超时等没有拿到 HTTP 响应的情况，status 为 0。
    public static func network(_ message: String = "网络连接失败") -> APIError {
        APIError(status: 0, detail: .text(message))
    }

    public var isNetwork: Bool { status == 0 }
    public var isUnauthorized: Bool { status == 401 }

    public var code: String? {
        if case .coded(let c, _, _) = detail { return c }
        return nil
    }

    public var message: String {
        switch detail {
        case .text(let s): return s
        case .coded(_, let m, _): return m
        case .validation(let items): return items.joined(separator: "；")
        }
    }

    public var errorDescription: String? { message }

    /// 409 冲突或重复时，服务端附带的整条记录。
    public var embeddedRecord: Record? {
        guard case .coded(_, _, let payload) = detail, case .object(let o) = payload, let r = o["record"] else { return nil }
        return try? JSONCoding.decoder.decode(Record.self, from: JSONCoding.encoder.encode(r))
    }

    public static func parse(status: Int, data: Data) -> APIError {
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: data), case .object(let o) = root, let detail = o["detail"] else {
            let text = String(data: data, encoding: .utf8).flatMap { $0.isEmpty ? nil : String($0.prefix(200)) }
            return APIError(status: status, detail: .text(text ?? "请求失败（\(status)）"))
        }
        switch detail {
        case .string(let s):
            return APIError(status: status, detail: .text(s))
        case .array(let items):
            let msgs = items.compactMap { item -> String? in
                guard case .object(let d) = item, case .string(let m)? = d["msg"] else { return nil }
                return m.hasPrefix("Value error, ") ? String(m.dropFirst("Value error, ".count)) : m
            }
            return APIError(status: status, detail: .validation(msgs.isEmpty ? ["参数不正确"] : msgs))
        case .object(let d):
            let code = d["code"]?.stringValue ?? ""
            let message = d["message"]?.stringValue ?? "请求失败（\(status)）"
            return APIError(status: status, detail: .coded(code: code, message: message, payload: detail))
        default:
            return APIError(status: status, detail: .text("请求失败（\(status)）"))
        }
    }
}
