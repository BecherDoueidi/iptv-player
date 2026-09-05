import Foundation
import SwiftData

public enum DownloadState: String, Codable {
    case queued, downloading, paused, completed, failed, cancelled
}

/// Soft-keyed by `contentKey` (movie or episode) — deliberately not a SwiftData
/// `@Relationship` to Movie/TVEpisode, since a Download can point at either kind.
@Model
public class Download {
    @Attribute(.unique) public var contentKey: String
    public var kindRaw: String
    public var stateRaw: String
    public var bytesReceived: Int64
    public var bytesExpected: Int64
    public var localFileURLString: String?
    public var resumeData: Data?
    public var sourceStreamURLString: String
    public var title: String
    public var createdAt: Date
    public var completedAt: Date?
    public var lastError: String?

    public init(
        contentKey: String,
        kind: ContentKind,
        state: DownloadState,
        bytesReceived: Int64 = 0,
        bytesExpected: Int64 = 0,
        localFileURLString: String? = nil,
        resumeData: Data? = nil,
        sourceStreamURLString: String,
        title: String,
        createdAt: Date = .now,
        completedAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.contentKey = contentKey
        self.kindRaw = kind.rawValue
        self.stateRaw = state.rawValue
        self.bytesReceived = bytesReceived
        self.bytesExpected = bytesExpected
        self.localFileURLString = localFileURLString
        self.resumeData = resumeData
        self.sourceStreamURLString = sourceStreamURLString
        self.title = title
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.lastError = lastError
    }

    public var kind: ContentKind {
        get { ContentKind(rawValue: kindRaw) ?? .movie }
        set { kindRaw = newValue.rawValue }
    }

    public var state: DownloadState {
        get { DownloadState(rawValue: stateRaw) ?? .failed }
        set { stateRaw = newValue.rawValue }
    }

    public var localFileURL: URL? {
        guard let localFileURLString else { return nil }
        return DownloadPaths.directory().appendingPathComponent(localFileURLString)
    }
}
