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
}
