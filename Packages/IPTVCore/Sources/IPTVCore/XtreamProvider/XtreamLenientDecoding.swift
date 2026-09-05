import Foundation

/// Real Xtream panels are inconsistent about whether numeric/boolean fields are sent
/// as JSON strings or as their native types (varies by panel software/version). Every
/// DTO in this module decodes leniently using these helpers so a quirky response
/// degrades gracefully instead of crashing the whole decode.
enum XtreamLenientDecoding {
    static func string<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, _ key: Key) -> String? {
        if let value = try? container.decode(String.self, forKey: key) { return value }
        if let value = try? container.decode(Int.self, forKey: key) { return String(value) }
        if let value = try? container.decode(Double.self, forKey: key) { return String(value) }
        return nil
    }

    static func int<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, _ key: Key) -> Int? {
        if let value = try? container.decode(Int.self, forKey: key) { return value }
        if let value = try? container.decode(String.self, forKey: key) { return Int(value) }
        return nil
    }

    static func double<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, _ key: Key) -> Double? {
        if let value = try? container.decode(Double.self, forKey: key) { return value }
        if let value = try? container.decode(String.self, forKey: key) { return Double(value) }
        return nil
    }

    static func bool<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, _ key: Key) -> Bool? {
        if let value = try? container.decode(Bool.self, forKey: key) { return value }
        if let value = try? container.decode(Int.self, forKey: key) { return value != 0 }
        if let value = try? container.decode(String.self, forKey: key) {
            return value == "1" || value.lowercased() == "true"
        }
        return nil
    }
}
