import Foundation

struct XtreamAuthResponseDTO: Decodable {
    let userInfo: XtreamUserInfoDTO?

    enum CodingKeys: String, CodingKey {
        case userInfo = "user_info"
    }
}

/// Real Xtream panels are inconsistent about whether numeric/boolean fields are sent
/// as JSON strings or as their native types (varies by panel software/version), and
/// some fields (like `exp_date`) can be null for unlimited accounts. Every field here
/// is decoded leniently so a quirky response degrades gracefully instead of crashing
/// the whole decode.
struct XtreamUserInfoDTO: Decodable {
    let username: String?
    let message: String?
    let auth: Int?
    let status: String?
    let expDateRaw: String?
    let isTrial: Bool?
    let activeConnections: Int?
    let maxConnections: Int?

    enum CodingKeys: String, CodingKey {
        case username, message, auth, status
        case expDateRaw = "exp_date"
        case isTrial = "is_trial"
        case activeConnections = "active_cons"
        case maxConnections = "max_connections"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        username = try? container.decode(String.self, forKey: .username)
        message = try? container.decode(String.self, forKey: .message)
        auth = Self.decodeLenientInt(container, .auth)
        status = try? container.decode(String.self, forKey: .status)
        expDateRaw = Self.decodeLenientString(container, .expDateRaw)
        isTrial = Self.decodeLenientBool(container, .isTrial)
        activeConnections = Self.decodeLenientInt(container, .activeConnections)
        maxConnections = Self.decodeLenientInt(container, .maxConnections)
    }

    private static func decodeLenientInt(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys
    ) -> Int? {
        if let value = try? container.decode(Int.self, forKey: key) { return value }
        if let text = try? container.decode(String.self, forKey: key) { return Int(text) }
        return nil
    }

    private static func decodeLenientString(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys
    ) -> String? {
        if let value = try? container.decode(String.self, forKey: key) { return value }
        if let value = try? container.decode(Int.self, forKey: key) { return String(value) }
        return nil
    }

    private static func decodeLenientBool(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys
    ) -> Bool? {
        if let value = try? container.decode(Bool.self, forKey: key) { return value }
        if let value = try? container.decode(Int.self, forKey: key) { return value != 0 }
        if let value = try? container.decode(String.self, forKey: key) {
            return value == "1" || value.lowercased() == "true"
        }
        return nil
    }
}
