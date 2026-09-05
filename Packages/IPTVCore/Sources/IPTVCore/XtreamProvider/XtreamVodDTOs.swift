import Foundation

struct XtreamCategoryDTO: Decodable {
    let categoryID: String?
    let categoryName: String?

    enum CodingKeys: String, CodingKey {
        case categoryID = "category_id"
        case categoryName = "category_name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        categoryID = XtreamLenientDecoding.string(container, .categoryID)
        categoryName = try? container.decode(String.self, forKey: .categoryName)
    }
}

/// One entry from `get_vod_streams` — the catalog list. Deliberately narrow: this
/// endpoint doesn't carry plot/genre/etc, only what's needed for browsing/grid display.
struct XtreamVodStreamDTO: Decodable {
    let streamID: String?
    let name: String?
    let streamIcon: String?
    let rating: Double?
    let categoryID: String?
    let containerExtension: String?
    let added: String?

    enum CodingKeys: String, CodingKey {
        case streamID = "stream_id"
        case name
        case streamIcon = "stream_icon"
        case rating
        case categoryID = "category_id"
        case containerExtension = "container_extension"
        case added
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        streamID = XtreamLenientDecoding.string(container, .streamID)
        name = try? container.decode(String.self, forKey: .name)
        streamIcon = try? container.decode(String.self, forKey: .streamIcon)
        rating = XtreamLenientDecoding.double(container, .rating)
        categoryID = XtreamLenientDecoding.string(container, .categoryID)
        containerExtension = try? container.decode(String.self, forKey: .containerExtension)
        added = XtreamLenientDecoding.string(container, .added)
    }
}

struct XtreamVodInfoResponseDTO: Decodable {
    let info: XtreamVodInfoDTO?
}

/// The `info` object from `get_vod_info` — full per-title metadata, fetched on demand.
struct XtreamVodInfoDTO: Decodable {
    let plot: String?
    let genre: String?
    let releaseDate: String?
    let durationSecs: Int?
    let backdropPath: [String]?
    let rating: Double?

    enum CodingKeys: String, CodingKey {
        case plot
        case genre
        case releaseDate = "releasedate"
        case durationSecs = "duration_secs"
        case backdropPath = "backdrop_path"
        case rating
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        plot = try? container.decode(String.self, forKey: .plot)
        genre = try? container.decode(String.self, forKey: .genre)
        releaseDate = try? container.decode(String.self, forKey: .releaseDate)
        durationSecs = XtreamLenientDecoding.int(container, .durationSecs)
        backdropPath = try? container.decode([String].self, forKey: .backdropPath)
        rating = XtreamLenientDecoding.double(container, .rating)
    }
}
