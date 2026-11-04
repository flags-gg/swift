import Foundation

/// Percentage rollouts. Must match the API and every other SDK exactly:
/// bucket = FNV-1a 32-bit of UTF-8 "<flag name>:<targeting key>", modulo 100.
public enum Rollout {
    public static func bucket(_ flagName: String, _ targetingKey: String) -> Int {
        var h: UInt32 = 0x811c9dc5
        for byte in "\(flagName):\(targetingKey)".utf8 {
            h ^= UInt32(byte)
            h = h &* 0x01000193
        }
        return Int(h % 100)
    }

    /// Without a key only a full rollout applies, so partial rollouts fail closed.
    public static func inRollout(_ flagName: String, _ targetingKey: String?, _ rollout: Int?) -> Bool {
        let pct = rollout ?? 100
        if pct >= 100 { return true }
        guard pct > 0, let key = targetingKey, !key.isEmpty else { return false }
        return bucket(flagName, key) < pct
    }

    /// The user as the server's targeting rules see it: base64 of UTF-8 JSON, with the targeting key as "key".
    public static func encodeContext(_ targetingKey: String?, _ context: [String: [String]]) -> String {
        var object: [String: Any] = context.mapValues { $0 as Any }
        if let key = targetingKey, !key.isEmpty { object["key"] = key }
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return data.base64EncodedString()
    }

    private static let installIdKey = "flagsgg.install-id"

    /// A stable id for this install, kept in UserDefaults, so "x% of phones" works without a user id.
    public static func installId(_ defaults: UserDefaults = .standard) -> String {
        if let id = defaults.string(forKey: installIdKey) { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: installIdKey)
        return id
    }
}
