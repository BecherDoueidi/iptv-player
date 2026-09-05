import Foundation

enum XtreamMapper {
    static func makeAccountInfo(from response: XtreamAuthResponseDTO) -> AccountInfo {
        guard let userInfo = response.userInfo else {
            return AccountInfo(isAuthenticated: false)
        }

        let expiresAt = userInfo.expDateRaw
            .flatMap(TimeInterval.init)
            .map { Date(timeIntervalSince1970: $0) }

        return AccountInfo(
            isAuthenticated: (userInfo.auth ?? 0) == 1,
            status: userInfo.status,
            isTrial: userInfo.isTrial,
            expiresAt: expiresAt,
            activeConnections: userInfo.activeConnections,
            maxConnections: userInfo.maxConnections,
            message: userInfo.message
        )
    }

    static func makeCategories(from dtos: [XtreamCategoryDTO]) -> [MediaCategory] {
        dtos.compactMap { dto in
            guard let id = dto.categoryID, let name = dto.categoryName else { return nil }
            return MediaCategory(id: id, name: name)
        }
    }

    static func makeMovieSummaries(from dtos: [XtreamVodStreamDTO]) -> [MovieSummary] {
        dtos.compactMap { dto in
            guard let id = dto.streamID, let title = dto.name else { return nil }
            return MovieSummary(
                id: id,
                categoryID: dto.categoryID,
                title: title,
                posterURL: dto.streamIcon.flatMap(URL.init(string:)),
                containerExtension: dto.containerExtension,
                rating: dto.rating,
                addedAt: dto.added.flatMap(TimeInterval.init).map { Date(timeIntervalSince1970: $0) }
            )
        }
    }

    static func makeLiveChannels(from dtos: [XtreamLiveStreamDTO]) -> [LiveChannelSummary] {
        dtos.compactMap { dto in
            guard let id = dto.streamID, let name = dto.name else { return nil }
            return LiveChannelSummary(
                id: id,
                categoryID: dto.categoryID,
                name: name,
                logoURL: dto.streamIcon.flatMap(URL.init(string:)),
                number: dto.number,
                // Panels send an empty string rather than omitting the field when a
                // channel has no EPG mapping.
                epgChannelID: dto.epgChannelID?.isEmpty == false ? dto.epgChannelID : nil
            )
        }
    }

    static func makeEPGEntries(from response: XtreamShortEPGResponseDTO) -> [EPGEntry] {
        response.listings.enumerated().compactMap { index, dto in
            guard let title = dto.title, !title.isEmpty else { return nil }
            return EPGEntry(
                id: dto.id ?? "listing-\(index)",
                title: title,
                description: dto.description?.isEmpty == false ? dto.description : nil,
                startsAt: dto.startsAt,
                endsAt: dto.endsAt
            )
        }
        .sorted { ($0.startsAt ?? .distantPast) < ($1.startsAt ?? .distantPast) }
    }

    static func makeSeriesSummaries(from dtos: [XtreamSeriesDTO]) -> [SeriesSummary] {
        dtos.compactMap { dto in
            guard let id = dto.seriesID, let title = dto.name else { return nil }
            return SeriesSummary(
                id: id,
                categoryID: dto.categoryID,
                title: title,
                posterURL: dto.cover.flatMap(URL.init(string:)),
                backdropURL: dto.backdropPath?.first.flatMap(URL.init(string:)),
                plot: dto.plot,
                genre: dto.genre,
                rating: dto.rating
            )
        }
    }

    static func makeSeriesDetail(id: String, from response: XtreamSeriesInfoResponseDTO) -> SeriesDetail {
        let seasons: [SeriesSeason] = response.episodes.compactMap { key, episodeDTOs -> SeriesSeason? in
            guard let seasonNumber = Int(key) else { return nil }
            let episodes = episodeDTOs.compactMap { dto -> SeriesEpisode? in
                guard let episodeID = dto.id, let episodeNumber = dto.episodeNum, let title = dto.title else { return nil }
                return SeriesEpisode(
                    id: episodeID,
                    seasonNumber: dto.season ?? seasonNumber,
                    episodeNumber: episodeNumber,
                    title: title,
                    containerExtension: dto.containerExtension
                )
            }.sorted { $0.episodeNumber < $1.episodeNumber }
            return SeriesSeason(seasonNumber: seasonNumber, episodes: episodes)
        }.sorted { $0.seasonNumber < $1.seasonNumber }

        return SeriesDetail(id: id, seasons: seasons)
    }

    static func makeMovieDetail(id: String, from response: XtreamVodInfoResponseDTO) -> MovieDetail {
        let info = response.info
        return MovieDetail(
            id: id,
            plot: info?.plot,
            genre: info?.genre,
            releaseDate: info?.releaseDate,
            durationSeconds: info?.durationSecs,
            backdropURL: info?.backdropPath?.first.flatMap(URL.init(string:)),
            rating: info?.rating
        )
    }
}
