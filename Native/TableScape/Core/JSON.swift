import Foundation

typealias JSONObject = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func string(_ key: String, _ fallback: String = "") -> String { self[key] as? String ?? fallback }
    func int(_ key: String, _ fallback: Int = 0) -> Int { (self[key] as? NSNumber)?.intValue ?? fallback }
    func double(_ key: String, _ fallback: Double = 0) -> Double { (self[key] as? NSNumber)?.doubleValue ?? fallback }
    func bool(_ key: String, _ fallback: Bool = false) -> Bool { (self[key] as? NSNumber)?.boolValue ?? fallback }
    func object(_ key: String) -> JSONObject { self[key] as? JSONObject ?? [:] }
    func objects(_ key: String) -> [JSONObject] { self[key] as? [JSONObject] ?? [] }
    func ints(_ key: String) -> [Int] { (self[key] as? [NSNumber])?.map(\.intValue) ?? [] }
    func doubles(_ key: String) -> [Double] { (self[key] as? [NSNumber])?.map(\.doubleValue) ?? [] }
    func strings(_ key: String) -> [String] {
        guard let values = self[key] as? [Any] else { return [] }
        return values.map {
            guard let text = $0 as? String else { return "" }
            if (key == "ops" || key == "buttons") && (text == "null" || text == "hidden") { return "" }
            return text
        }
    }
    func int(_ key: String, default fallback: Int) -> Int { int(key, fallback) }
    func double(_ key: String, default fallback: Double) -> Double { double(key, fallback) }
    func string(_ key: String, default fallback: String) -> String { string(key, fallback) }
    func bool(_ key: String, default fallback: Bool) -> Bool { bool(key, fallback) }
}

func gamePlain(_ text: String) -> String {
    text.replacingOccurrences(of: "@[a-zA-Z0-9]{3}@|<[^>]*>", with: "", options: .regularExpression)
        .replacingOccurrences(of: "|", with: "\n")
}

enum GameTransportError: Error, LocalizedError {
    case http(Int, String), invalid(String), superseded
    var errorDescription: String? {
        switch self {
        case .http(401, _): return "Your game session has ended."
        case .http(403, _): return "This connection is not permitted by the game server."
        case .http(let code, _) where code >= 500: return "TableScape is temporarily unavailable."
        case .http(let code, let reason) where code == 429 || reason == "Native session limit reached": return "The server is busy. Please try again shortly."
        case .http(_, "Character is already logged in"): return "Your previous session is still closing."
        case .http(_, let reason) where reason.hasPrefix("Use a local test name"): return "Choose unity followed by up to seven lowercase letters, numbers or underscores."
        case .http(_, let reason): return reason.isEmpty ? "The game request could not be completed." : reason
        case .invalid(let reason): return reason
        case .superseded: return "The session changed."
        }
    }
    var retryable: Bool {
        switch self {
        case .http(let code, let reason): return code == 429 || code >= 500 || reason == "Character is already logged in" || reason == "Native session limit reached"
        default: return false
        }
    }
}

enum GameContract {
    static let tabNames = ["Combat", "Skills", "Quests", "Inventory", "Equipment", "Prayer", "Magic", "Unused", "Friends", "Ignore", "Logout", "Settings", "Controls", "Music"]
    static let tabIcons = [0, 1, 2, 3, 4, 5, 6, -1, 7, 8, 9, 10, 11, 12]
    static let skillNames = ["Attack", "Defence", "Strength", "Hitpoints", "Ranged", "Prayer", "Magic", "Cooking", "Woodcutting", "Fletching", "Fishing", "Firemaking", "Crafting", "Smithing", "Mining", "Herblore", "Agility", "Thieving", "", "", "Runecraft"]
    static func identity(kind: String, actor: JSONObject) -> String {
        kind + ":" + (actor.string("key").isEmpty ? String(actor.int("id")) : actor.string("key"))
    }
    static func itemIdentity(_ item: JSONObject) -> String { "\(item.int("component")):\(item.int("slot")):\(item.int("id"))" }
}
