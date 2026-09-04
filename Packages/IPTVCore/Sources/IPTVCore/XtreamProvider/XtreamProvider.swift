import Foundation

public final class XtreamProvider: MediaProvider {
    private let apiClient: XtreamAPIClient

    public init(urlSession: URLSession = .shared) {
        self.apiClient = XtreamAPIClient(urlSession: urlSession)
    }

    public func authenticate(credentials: XtreamCredentials) async throws -> AccountInfo {
        let response = try await apiClient.fetchAuthResponse(credentials: credentials)
        return XtreamMapper.makeAccountInfo(from: response)
    }
}
