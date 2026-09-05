import Foundation

/// One entry from `get_series` — unlike movies, this list already carries plot/genre/
/// rating/backdrop, so no separate detail call is needed just to browse.
struct XtreamSeriesDTO: Decodable {
    let seriesID: String?
    let name: String?
    let cover: String?
    let backdropPath: [String]?
    let plot: String?
    let genre: String?
    let rating: Double?
    let categoryID: String?

    enum CodingKeys: String, CodingKey {
        case seriesID = "series_id"
        case name, cover
        case backdropPath = "backdrop_path"
        case plot, genre, rating
        case categoryID = "category_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seriesID = XtreamLenientDecoding.string(container, .seriesID)
        name = try? container.decode(String.self, forKey: .name)
        cover = try? container.decode(String.self, forKey: .cover)
        backdropPath = try? container.decode([String].self, forKey: .backdropPath)
        plot = try? container.decode(String.self, forKey: .plot)
        genre = try? container.decode(String.self, forKey: .genre)
        rating = XtreamLenientDecoding.double(container, .rating)
        categoryID = XtreamLenientDecoding.string(container, .categoryID)
    }
}

struct XtreamEpisodeDTO: Decodable {
    let id: String?
    let episodeNum: Int?
    let title: String?
    let containerExtension: String?
    let season: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, season
        case episodeNum = "episode_num"
        case containerExtension = "container_extension"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = XtreamLenientDecoding.string(container, .id)
        episodeNum = XtreamLenientDecoding.int(container, .episodeNum)
        title = try? container.decode(String.self, forKey: .title)
        containerExtension = try? container.decode(String.self, forKey: .containerExtension)
        season = XtreamLenientDecoding.int(container, .season)
    }
}

/// `get_series_info`'s `episodes` field is a dictionary keyed by season number
/// ("1", "2", ...) mapping to that season's episode array. Some panels send `[]`
/// instead of `{}` when a series has no episodes yet — tolerate that as empty
/// rather than throwing, since it's a real observed quirk, not a hypothetical one.
struct XtreamSeriesInfoResponseDTO: Decodable {
    let episodes: [String: [XtreamEpisodeDTO]]

    enum CodingKeys: String, CodingKey {
        case episodes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        episodes = (try? container.decode([String: [XtreamEpisodeDTO]].self, forKey: .episodes)) ?? [:]
    }
}
