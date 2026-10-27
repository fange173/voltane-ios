import Foundation
import Security

public struct StoredToken: Codable, Sendable, Equatable {
    public var token: String
    public var expiresAt: Date
    public var refreshedAt: Date

    public init(token: String, expiresAt: Date, refreshedAt: Date = Date()) {
        self.token = token; self.expiresAt = expiresAt; self.refreshedAt = refreshedAt
    }
}

/// 令牌只存在 Keychain，不写 UserDefaults，也不进日志。
public protocol TokenStore: Sendable {
    func load() -> StoredToken?
    func save(_ token: StoredToken) throws
    func clear()
}

public struct KeychainError: Error, Sendable { public let status: OSStatus }

public final class KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String

    public init(service: String = "io.github.fange173.voltane", account: String = "session-token") {
        self.service = service; self.account = account
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public func load() -> StoredToken? {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(StoredToken.self, from: data)
    }

    public func save(_ token: StoredToken) throws {
        let data = try JSONEncoder().encode(token)
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError(status: status) }
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    }

    public func clear() { SecItemDelete(baseQuery as CFDictionary) }
}

/// 测试和预览用的内存实现。
public final class MemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: StoredToken?

    public init(_ value: StoredToken? = nil) { self.value = value }

    public func load() -> StoredToken? { lock.withLock { value } }
    public func save(_ token: StoredToken) throws { lock.withLock { value = token } }
    public func clear() { lock.withLock { value = nil } }
}
