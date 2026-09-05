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
        auth = XtreamLenientDecoding.int(container, .auth)
        status = try? container.decode(String.self, forKey: .status)
        expDateRaw = XtreamLenientDecoding.string(container, .expDateRaw)
        isTrial = XtreamLenientDecoding.bool(container, .isTrial)
        activeConnections = XtreamLenientDecoding.int(container, .activeConnections)
        maxConnections = XtreamLenientDecoding.int(container, .maxConnections)
    }
}
