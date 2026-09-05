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
