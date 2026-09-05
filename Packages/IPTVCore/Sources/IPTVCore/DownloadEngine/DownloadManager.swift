import Foundation
import SwiftData

public enum DownloadError: Error {
    case insufficientDiskSpace
}

/// Owns the one shared background `URLSession` for the app. Delegate callbacks are
/// received on the main queue (`delegateQueue: .main`) specifically so they can touch
/// SwiftData's `ModelContext` directly without cross-actor `Sendable` machinery — a
/// deliberate simplification appropriate for a personal app, not a general pattern.
@MainActor
public final class DownloadManager: NSObject {
    public static let backgroundSessionIdentifier = "com.personal.iptvplayer.downloads"
    private static let minimumValidFileSizeBytes: Int64 = 100_000 // sanity floor, not a real size estimate
    private static let minimumFreeDiskSpaceBytes: Int64 = 200_000_000 // 200 MB safety margin

    private var session: URLSession!
    private var modelContext: ModelContext?
    private var backgroundCompletionHandler: (() -> Void)?
    private var tasksByContentKey: [String: URLSessionDownloadTask] = [:]
    private var lastProgressSaveAt: [String: Date] = [:]

    public override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    /// Must be called once at app launch before enqueueing anything — reconnects to
    /// any tasks the OS kept alive/queued while the app was suspended or killed.
    public func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        session.getAllTasks { [weak self] tasks in
            Task { @MainActor in
                self?.reconcile(liveTasks: tasks)
            }
        }
    }

    /// Called from `AppDelegate.application(_:handleEventsForBackgroundURLSession:completionHandler:)`.
    public func handleBackgroundEvents(completionHandler: @escaping () -> Void) {
        backgroundCompletionHandler = completionHandler
    }

    public func enqueue(contentKey: String, kind: ContentKind, title: String, sourceURL: URL) throws {
        guard let modelContext else { return }

        let descriptor = FetchDescriptor<Download>(predicate: #Predicate { $0.contentKey == contentKey })
        if let existing = try? modelContext.fetch(descriptor).first,
           existing.state == .downloading || existing.state == .queued || existing.state == .completed {
            return
        }

        guard hasSufficientDiskSpace() else {
            throw DownloadError.insufficientDiskSpace
        }

        let download = Download(
            contentKey: contentKey,
            kind: kind,
            state: .queued,
            sourceStreamURLString: sourceURL.absoluteString,
            title: title
        )
        modelContext.insert(download)
        try? modelContext.save()

        startTask(for: download, url: sourceURL)
    }

    public func pause(contentKey: String) {
        guard let task = tasksByContentKey[contentKey] else { return }
        task.cancel { [weak self] data in
            Task { @MainActor in
                self?.applyPause(contentKey: contentKey, resumeData: data)
            }
        }
    }

    public func resume(contentKey: String) {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<Download>(predicate: #Predicate { $0.contentKey == contentKey })
        guard let download = try? modelContext.fetch(descriptor).first else { return }

        let task: URLSessionDownloadTask
        if let resumeData = download.resumeData {
            task = session.downloadTask(withResumeData: resumeData)
        } else if let url = URL(string: download.sourceStreamURLString) {
            task = session.downloadTask(with: url)
        } else {
            return
        }
        task.taskDescription = contentKey
        tasksByContentKey[contentKey] = task
        download.resumeData = nil
        download.state = .downloading
        try? modelContext.save()
        task.resume()
    }

    public func retry(contentKey: String) {
        resume(contentKey: contentKey)
    }

    public func cancel(contentKey: String) {
        guard let modelContext else { return }
        tasksByContentKey[contentKey]?.cancel()
        tasksByContentKey[contentKey] = nil

        let descriptor = FetchDescriptor<Download>(predicate: #Predicate { $0.contentKey == contentKey })
        guard let download = try? modelContext.fetch(descriptor).first else { return }
        if let fileURL = download.localFileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        modelContext.delete(download)
        try? modelContext.save()
    }

    // MARK: - Private

    private func startTask(for download: Download, url: URL) {
        let task = session.downloadTask(with: url)
        task.taskDescription = download.contentKey
        tasksByContentKey[download.contentKey] = task
        download.state = .downloading
        try? modelContext?.save()
        task.resume()
    }

    private func applyPause(contentKey: String, resumeData: Data?) {
        tasksByContentKey[contentKey] = nil
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<Download>(predicate: #Predicate { $0.contentKey == contentKey })
        guard let download = try? modelContext.fetch(descriptor).first else { return }
        download.resumeData = resumeData
        download.state = .paused
        try? modelContext.save()
    }

    private func hasSufficientDiskSpace() -> Bool {
        guard let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
            let available = values.volumeAvailableCapacityForImportantUsage
        else {
            return true // fail open — don't block downloads if capacity can't be determined
        }
        return available > Self.minimumFreeDiskSpaceBytes
    }

    /// Cross-references live OS-tracked tasks against persisted rows so the UI never
    /// shows a stale "downloading" state after a relaunch. Orphaned rows (no live task,
    /// no completed file) are marked failed; orphaned files with no row are removed.
    private func reconcile(liveTasks: [URLSessionTask]) {
        guard let modelContext else { return }

        let liveByKey = Dictionary(uniqueKeysWithValues: liveTasks.compactMap { task -> (String, URLSessionDownloadTask)? in
            guard let key = task.taskDescription, let downloadTask = task as? URLSessionDownloadTask else { return nil }
            return (key, downloadTask)
        })

        guard let downloads = try? modelContext.fetch(FetchDescriptor<Download>()) else { return }
        for download in downloads {
            if let task = liveByKey[download.contentKey] {
                tasksByContentKey[download.contentKey] = task
                continue
            }
            switch download.state {
            case .downloading, .queued:
                if let fileURL = download.localFileURL, FileManager.default.fileExists(atPath: fileURL.path) {
                    download.state = .completed
                } else {
                    download.state = .failed
                    download.lastError = "Download stopped while the app was closed."
                }
            case .paused, .completed, .failed, .cancelled:
                break
            }
        }
        try? modelContext.save()

        cleanUpOrphanedFiles(knownDownloads: downloads)
    }

    private func cleanUpOrphanedFiles(knownDownloads: [Download]) {
        let knownFileNames = Set(knownDownloads.compactMap(\.localFileURLString))
        let directory = DownloadPaths.directory()
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for file in files where !knownFileNames.contains(file) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    // `nonisolated` + `MainActor.assumeIsolated`, not `Task { @MainActor in }`, because
    // the temp file at `location` is deleted the instant this method returns — it must
    // be moved synchronously, not after hopping to the main actor on a later run loop turn.
    public nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        MainActor.assumeIsolated {
            guard let contentKey = downloadTask.taskDescription, let modelContext else { return }
            let descriptor = FetchDescriptor<Download>(predicate: #Predicate { $0.contentKey == contentKey })
            guard let download = try? modelContext.fetch(descriptor).first else { return }

            let ext = URL(string: download.sourceStreamURLString)?.pathExtension
            let safeExt = (ext?.isEmpty == false) ? ext! : "mp4"
            let fileName = "\(contentKey.replacingOccurrences(of: "|", with: "_")).\(safeExt)"
            let destination = DownloadPaths.directory().appendingPathComponent(fileName)

            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: location, to: destination)

                let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
                let fileSize = (attributes[.size] as? Int64) ?? 0
                guard fileSize > Self.minimumValidFileSizeBytes else {
                    try? FileManager.default.removeItem(at: destination)
                    download.state = .failed
                    download.lastError = "Downloaded file looked invalid (too small) — the stream may not support downloading."
                    try? modelContext.save()
                    return
                }

                download.localFileURLString = fileName
                download.bytesReceived = fileSize
                download.state = .completed
                download.completedAt = .now
                try? modelContext.save()
            } catch {
                download.state = .failed
                download.lastError = error.localizedDescription
                try? modelContext.save()
            }
        }
    }

    public nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        MainActor.assumeIsolated {
            guard let contentKey = downloadTask.taskDescription, let modelContext else { return }
            let descriptor = FetchDescriptor<Download>(predicate: #Predicate { $0.contentKey == contentKey })
            guard let download = try? modelContext.fetch(descriptor).first else { return }

            download.bytesReceived = totalBytesWritten
            if totalBytesExpectedToWrite > 0 {
                download.bytesExpected = totalBytesExpectedToWrite
            }

            // Throttle persistence writes — the in-memory @Model mutation above already
            // updates any observing UI immediately; saving every tick would hammer disk I/O.
            let now = Date()
            if lastProgressSaveAt[contentKey].map({ now.timeIntervalSince($0) > 2 }) ?? true {
                lastProgressSaveAt[contentKey] = now
                try? modelContext.save()
            }
        }
    }

    public nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        MainActor.assumeIsolated {
            guard let error, let contentKey = task.taskDescription, let modelContext else { return }
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled {
                return // explicit pause/cancel already handled its own state transition
            }
            let descriptor = FetchDescriptor<Download>(predicate: #Predicate { $0.contentKey == contentKey })
            guard let download = try? modelContext.fetch(descriptor).first else { return }
            if let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                download.resumeData = resumeData
            }
            download.state = .failed
            download.lastError = error.localizedDescription
            try? modelContext.save()
        }
    }

    public nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        MainActor.assumeIsolated {
            backgroundCompletionHandler?()
            backgroundCompletionHandler = nil
        }
    }
}
