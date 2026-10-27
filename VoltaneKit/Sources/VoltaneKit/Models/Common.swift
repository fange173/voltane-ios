import Foundation

public struct UserBrief: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let username: String?
    public let name: String
    public let color: String?

    public init(id: Int, username: String?, name: String, color: String?) {
        self.id = id; self.username = username; self.name = name; self.color = color
    }
}

/// 登录用户。`settings` 是服务端合并保存的偏好（主题、默认车辆、付款人开关等）。
public struct User: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let username: String
    public let name: String
    public let color: String?
    public let role: String
    public let isAdmin: Bool
    public let mustChangePassword: Bool
    public var settings: [String: JSONValue]

    public var brief: UserBrief { UserBrief(id: id, username: username, name: name, color: color) }
}

/// 登录、注册返回的用户资料；`client=ios` 时附带令牌。
public struct LoginResponse: Decodable, Sendable {
    public let user: User
    public let token: String?
    public let expiresAt: UTCDateTime?
    public let cookieSecure: Bool?

    private enum Keys: String, CodingKey { case token, expiresAt, cookieSecure }

    public init(from decoder: Decoder) throws {
        user = try User(from: decoder)
        let c = try decoder.container(keyedBy: Keys.self)
        token = try c.decodeIfPresent(String.self, forKey: .token)
        expiresAt = try c.decodeIfPresent(UTCDateTime.self, forKey: .expiresAt)
        cookieSecure = try c.decodeIfPresent(Bool.self, forKey: .cookieSecure)
    }
}

public struct TokenResponse: Decodable, Sendable {
    public let token: String
    public let expiresAt: UTCDateTime
}

public struct OKResponse: Decodable, Sendable { public let ok: Bool? }

public struct Health: Decodable, Sendable {
    public let ok: Bool
    public let service: String
    public let version: String
    public let apiVersion: Int?
    public let tz: String?
    public let serverTime: LocalDateTime?
}

public enum Quality: String, Codable, Sendable, CaseIterable {
    case a = "A", b = "B", c = "C", d = "D"

    public var label: String {
        switch self { case .a: "精确"; case .b: "估"; case .c: "粗略"; case .d: "不足" }
    }
}

public struct Member: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let username: String
    public let name: String
    public let color: String?
    public let role: String
    public let roleLabel: String
    public let isMe: Bool
    public let joinedAt: UTCDateTime?
}

public struct Invite: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let code: String
    public let role: String
    public let roleLabel: String
    public let allowSignup: Bool
    /// 空表示不限次数。
    public let maxUses: Int?
    public let usedCount: Int
    /// 空表示长期有效。
    public let expiresAt: UTCDateTime?
    public let lastUsedAt: UTCDateTime?
}

public struct InvitePreview: Decodable, Sendable {
    public let allowSignup: Bool
    public let inviter: String
    public let role: String
    public let roleLabel: String
    public let vehicleName: String
}

public struct AcceptInvite: Decodable, Sendable {
    public let vehicleId: Int
    public let already: Bool?
}

public struct Activity: Codable, Sendable, Identifiable {
    public let id: Int
    public let action: String
    public let entity: String
    public let entityId: Int?
    public let summary: String
    public let createdAt: UTCDateTime
    public let user: UserBrief?
}
