import Foundation
import VoltaneKit

/// 保存在本机的偏好：服务器地址、主题、当前车辆、草稿。令牌不在这里，只存 Keychain。
struct AppSettings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var server: ServerConfig? {
        get { defaults.data(forKey: "server-config").flatMap { try? JSONDecoder().decode(ServerConfig.self, from: $0) } }
        nonmutating set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) { defaults.set(data, forKey: "server-config") }
            else { defaults.removeObject(forKey: "server-config") }
        }
    }

    var theme: String {
        get { defaults.string(forKey: "theme") ?? "auto" }
        nonmutating set { defaults.set(newValue, forKey: "theme") }
    }

    var lastUsername: String {
        get { defaults.string(forKey: "last-username") ?? "" }
        nonmutating set { defaults.set(newValue, forKey: "last-username") }
    }

    var lastRefresh: Date? {
        get { defaults.object(forKey: "last-refresh") as? Date }
        nonmutating set { defaults.set(newValue, forKey: "last-refresh") }
    }

    func vehicleId(scope: String) -> Int? { defaults.object(forKey: "vid:\(scope)") as? Int }
    func setVehicleId(_ id: Int?, scope: String) { defaults.set(id, forKey: "vid:\(scope)") }

    func draft(key: String) -> FormDraft? {
        guard let d = defaults.data(forKey: "draft:\(key)"), let draft = try? JSONDecoder().decode(FormDraft.self, from: d), draft.isFresh else { return nil }
        return draft
    }

    func saveDraft(_ draft: FormDraft?, key: String) {
        if let draft, draft.hasContent, let data = try? JSONEncoder().encode(draft) { defaults.set(data, forKey: "draft:\(key)") }
        else { defaults.removeObject(forKey: "draft:\(key)") }
    }

    /// 同一个自定义地点名用到第 2 次时询问是否存为常用地点。
    func placeNameCount(_ key: String) -> Int { (defaults.dictionary(forKey: "place-names") as? [String: Int])?[key] ?? 0 }
    func bumpPlaceName(_ key: String) -> Int {
        var d = (defaults.dictionary(forKey: "place-names") as? [String: Int]) ?? [:]
        d[key, default: 0] += 1
        defaults.set(d, forKey: "place-names")
        return d[key] ?? 0
    }

    func placeSuggestionSkipped(_ key: String) -> Bool { (defaults.stringArray(forKey: "place-skip") ?? []).contains(key) }
    func skipPlaceSuggestion(_ key: String) {
        defaults.set((defaults.stringArray(forKey: "place-skip") ?? []) + [key], forKey: "place-skip")
    }
}
