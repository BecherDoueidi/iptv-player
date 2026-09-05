import Foundation
import SwiftData

public enum DownloadError: Error {
    case insufficientDiskSpace
}

/// Owns the one shared download `URLSession` for the app. Delegate callbacks are
/// received on the main queue (`delegateQueue: .main`) specifically so they can touch
/// SwiftData's `ModelContext` directly without cross-actor `Sendable` machinery — a
/// deliberate simplification appropriate for a personal app, not a general pattern.
///
/// Transfers are *segmented*: panels routinely close the connection long before the
/// declared `Content-Length`, which `URLSession` reports as a perfectly successful
/// (but truncated) download. Each segment is appended to a `.part` file and the next
/// segment is requested with `Range: bytes=<offset>-`, so a stalled transfer continues
/// where it stopped instead of silently producing a broken file.
@MainActor
public final class DownloadManager: NSObject {
    private static let minimumValidFileSizeBytes: Int64 = 100_000 // sanity floor, not a real size estimate
    private static let minimumFreeDiskSpaceBytes: Int64 = 200_000_000 // 200 MB safety margin
    /// Generous, because a flaky panel may drop the connection many times over a
    /// multi-gigabyte file — but bounded, so a server that will never serve the whole
    /// file fails visibly instead of retrying forever.
    private static let maximumSegmentAttempts = 500
    /// Sent because some panels truncate or refuse transfers for unrecognised clients.
    private static let playerUserAgent = "VLC/3.0.20 LibVLC/3.0.20"

    private var session: URLSession!
    private var modelContext: ModelContext?
    private var tasksByContentKey: [String: URLSessionDownloadTask] = [:]
    private var lastProgressSaveAt: [String: Date] = [:]
    /// Avoids a SwiftData fetch inside `didWriteData`, which fires many times per
    /// second — a query per callback on the main thread was starving the transfer.
    private var downloadsByContentKey: [String: Download] = [:]
    /// Bytes already on disk when the in-flight segment started, so progress reported
    /// by the current (ranged) task can be shown as progress through the whole file.
    private var segmentBaseBytes: [String: Int64] = [:]
    private var segmentAttempts: [String: Int] = [:]

    // `nonisolated` so this can be constructed from AppDependencies' own nonisolated
    // init (which itself must stay nonisolated — see EnvironmentKey.defaultValue).
    // Legal here because initial stored-property assignment is exempt from actor
    // isolation checks; nothing in this init reads previously-isolated state.
    public nonisolated override init() {
        super.init()
        // Deliberately a *default* session, not `.background`. The background session
        // transfers out-of-process through nsurlsessiond, which negotiates with these
        // panels differently than a normal in-process client (VLC plays the very same
        // URLs fine) and was being cut off after a few kilobytes. Losing out-of-process
        // transfer is affordable now that segments resume from the `.part` file: a
        // download interrupted by backgrounding simply continues on next launch.
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60 * 60 * 12
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

    public func enqueue(contentKey: String, kind: ContentKind, title: String, sourceURL: URL) throws {
        guard let modelContext else { return }

        if let existing = cachedDownload(forKey: contentKey),
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
        downloadsByContentKey[contentKey] = download
        // A fresh enqueue starts from zero — drop any partial left by a previous attempt.
        try? FileManager.default.removeItem(at: partFileURL(for: contentKey))
        segmentAttempts[contentKey] = 0
        try? modelContext.save()

        startSegment(for: download)
    }

    public func pause(contentKey: String) {
        guard let task = tasksByContentKey[contentKey] else { return }
        task.cancel { [weak self] _ in
            Task { @MainActor in
                // Resume data is deliberately unused: continuation is driven by the
                // `.part` file's size, which survives relaunches and app termination.
                self?.applyPause(contentKey: contentKey)
            }
        }
    }

    public func resume(contentKey: String) {
        guard let download = cachedDownload(forKey: contentKey) else { return }
        segmentAttempts[contentKey] = 0
        download.lastError = nil
        startSegment(for: download)
    }

    public func retry(contentKey: String) {
        resume(contentKey: contentKey)
    }

    /// Called when the app returns to the foreground. Transfers can only run while the
    /// app is active (see `init`), so anything left mid-flight is picked up here —
    /// continuing from the `.part` file rather than restarting.
    public func resumeInterruptedDownloads() {
        guard let modelContext else { return }
        guard let downloads = try? modelContext.fetch(FetchDescriptor<Download>()) else { return }
        for download in downloads where download.state == .downloading || download.state == .queued {
            guard tasksByContentKey[download.contentKey] == nil else { continue }
            downloadsByContentKey[download.contentKey] = download
            segmentAttempts[download.contentKey] = 0
            startSegment(for: download)
        }
    }

    public func cancel(contentKey: String) {
        guard let modelContext else { return }
        tasksByContentKey[contentKey]?.cancel()
        tasksByContentKey[contentKey] = nil

        guard let download = cachedDownload(forKey: contentKey) else { return }
        if let fileURL = download.localFileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        try? FileManager.default.removeItem(at: partFileURL(for: contentKey))
        downloadsByContentKey[contentKey] = nil
        lastProgressSaveAt[contentKey] = nil
        segmentBaseBytes[contentKey] = nil
        segmentAttempts[contentKey] = nil
        modelContext.delete(download)
        try? modelContext.save()
    }

    // MARK: - Private

    /// Cached lookup — only falls back to a query the first time a key is seen.
    private func cachedDownload(forKey key: String) -> Download? {
        if let cached = downloadsByContentKey[key] { return cached }
        guard let modelContext else { return nil }
        let descriptor = FetchDescriptor<Download>(predicate: #Predicate { $0.contentKey == key })
        guard let found = try? modelContext.fetch(descriptor).first else { return nil }
        downloadsByContentKey[key] = found
        return found
    }

    private func sanitizedFileStem(for contentKey: String) -> String {
        contentKey.replacingOccurrences(of: "|", with: "_")
    }

    private func partFileURL(for contentKey: String) -> URL {
        DownloadPaths.directory().appendingPathComponent("\(sanitizedFileStem(for: contentKey)).part")
    }

    private func bytesOnDisk(for contentKey: String) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: partFileURL(for: contentKey).path)
        return (attributes?[.size] as? Int64) ?? 0
    }

    /// Starts (or continues) a transfer, requesting only the bytes not already on disk.
    private func startSegment(for download: Download) {
        guard let url = URL(string: download.sourceStreamURLString) else {
            fail(download, message: "The stream address is no longer valid.")
            return
        }

        let contentKey = download.contentKey
        let offset = bytesOnDisk(for: contentKey)

        var request = URLRequest(url: url)
        request.setValue(Self.playerUserAgent, forHTTPHeaderField: "User-Agent")
        if offset > 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }

        let task = session.downloadTask(with: request)
        task.taskDescription = contentKey
        tasksByContentKey[contentKey] = task
        segmentBaseBytes[contentKey] = offset
        download.bytesReceived = offset
        download.state = .downloading
        try? modelContext?.save()
        task.resume()
    }

    private func applyPause(contentKey: String) {
        tasksByContentKey[contentKey] = nil
        guard let modelContext, let download = cachedDownload(forKey: contentKey) else { return }
        download.bytesReceived = bytesOnDisk(for: contentKey)
        download.state = .paused
        try? modelContext.save()
    }

    private func fail(_ download: Download, message: String) {
        tasksByContentKey[download.contentKey] = nil
        download.state = .failed
        download.lastError = message
        try? modelContext?.save()
    }

    /// Appends a finished segment's temp file onto the `.part` file, returning the new
    /// total size on disk. Must run synchronously inside the delegate callback — the
    /// temp file is deleted the moment the callback returns.
    private func appendSegment(at location: URL, to partURL: URL) throws -> Int64 {
        if !FileManager.default.fileExists(atPath: partURL.path) {
            try FileManager.default.moveItem(at: location, to: partURL)
        } else {
            let handle = try FileHandle(forWritingTo: partURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            // Streamed in chunks so a multi-hundred-megabyte segment never has to be
            // resident in memory all at once.
            let reader = try FileHandle(forReadingFrom: location)
            defer { try? reader.close() }
            while let chunk = try reader.read(upToCount: 1_048_576), !chunk.isEmpty {
                try handle.write(contentsOf: chunk)
            }
            try? FileManager.default.removeItem(at: location)
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: partURL.path)
        return (attributes[.size] as? Int64) ?? 0
    }

    private func finish(_ download: Download, partURL: URL, totalBytes: Int64) {
        guard let modelContext else { return }
        let contentKey = download.contentKey

        guard totalBytes > Self.minimumValidFileSizeBytes else {
            try? FileManager.default.removeItem(at: partURL)
            fail(download, message: "The server sent only \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)) — this stream doesn't appear to allow downloading.")
            return
        }

        let ext = URL(string: download.sourceStreamURLString)?.pathExtension
        let safeExt = (ext?.isEmpty == false) ? ext! : "mp4"
        let fileName = "\(sanitizedFileStem(for: contentKey)).\(safeExt)"
        let destination = DownloadPaths.directory().appendingPathComponent(fileName)

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: partURL, to: destination)
            download.localFileURLString = fileName
            download.bytesReceived = totalBytes
            download.state = .completed
            download.completedAt = .now
            download.lastError = nil
            tasksByContentKey[contentKey] = nil
            try? modelContext.save()
        } catch {
            fail(download, message: error.localizedDescription)
        }
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
    /// shows a stale "downloading" state after a relaunch. Orphaned rows keep their
    /// `.part` file, so the user can resume rather than restart from zero.
    private func reconcile(liveTasks: [URLSessionTask]) {
        guard let modelContext else { return }

        let liveByKey = Dictionary(uniqueKeysWithValues: liveTasks.compactMap { task -> (String, URLSessionDownloadTask)? in
            guard let key = task.taskDescription, let downloadTask = task as? URLSessionDownloadTask else { return nil }
            return (key, downloadTask)
        })

        guard let downloads = try? modelContext.fetch(FetchDescriptor<Download>()) else { return }
        for download in downloads {
            downloadsByContentKey[download.contentKey] = download
            if let task = liveByKey[download.contentKey] {
                tasksByContentKey[download.contentKey] = task
                continue
            }
            switch download.state {
            case .downloading, .queued:
                if let fileURL = download.localFileURL, FileManager.default.fileExists(atPath: fileURL.path) {
                    download.state = .completed
                } else {
                    // Left as `.downloading` on purpose: `resumeInterruptedDownloads()`
                    // runs right after this and continues it from the `.part` file.
                    download.state = .downloading
                    download.bytesReceived = bytesOnDisk(for: download.contentKey)
                }
            case .paused, .completed, .failed, .cancelled:
                break
            }
        }
        try? modelContext.save()

        cleanUpOrphanedFiles(knownDownloads: downloads)
    }

    private func cleanUpOrphanedFiles(knownDownloads: [Download]) {
        var knownFileNames = Set(knownDownloads.compactMap(\.localFileURLString))
        // A `.part` belonging to a known row is work in progress, not an orphan.
        knownFileNames.formUnion(knownDownloads.map { "\(sanitizedFileStem(for: $0.contentKey)).part" })
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
            guard let contentKey = downloadTask.taskDescription else { return }
            guard let download = cachedDownload(forKey: contentKey) else { return }

            let http = downloadTask.response as? HTTPURLResponse
            if let http, !(200...299).contains(http.statusCode) {
                try? FileManager.default.removeItem(at: location)
                fail(download, message: "The server refused the download (HTTP \(http.statusCode)).")
                return
            }

            let partURL = partFileURL(for: contentKey)
            let base = segmentBaseBytes[contentKey] ?? 0
            // 200 in reply to a `Range` request means the server ignored it and restarted
            // from byte zero. Appending that would duplicate bytes and corrupt the file,
            // so the partial is discarded and this segment replaces it wholesale.
            let rangeIgnored = base > 0 && http?.statusCode == 200
            if rangeIgnored {
                try? FileManager.default.removeItem(at: partURL)
            }

            let totalBytes: Int64
            do {
                totalBytes = try appendSegment(at: location, to: partURL)
            } catch {
                fail(download, message: error.localizedDescription)
                return
            }

            download.bytesReceived = totalBytes
            tasksByContentKey[contentKey] = nil

            // The panel closed the connection early — `URLSession` calls this a success,
            // so truncation has to be detected here by comparing against Content-Length.
            let expected = download.bytesExpected
            guard expected > 0, totalBytes < expected else {
                finish(download, partURL: partURL, totalBytes: totalBytes)
                return
            }

            guard !rangeIgnored else {
                // Retrying would just fetch the same truncated prefix forever.
                try? FileManager.default.removeItem(at: partURL)
                fail(download, message: "The server cuts the transfer short and doesn't support resuming, so this stream can't be downloaded.")
                return
            }
            continueOrFail(download, madeProgress: totalBytes > base)
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

            // Throttle the *model mutation itself*, not just the save. This fires many
            // times per second, and every mutation makes SwiftData notify each @Query
            // observing Download — which re-renders whole episode lists on the main
            // thread, starving the very delegate callbacks driving the transfer.
            // Once per second is plenty for a progress bar.
            let now = Date()
            guard lastProgressSaveAt[contentKey].map({ now.timeIntervalSince($0) >= 1 }) ?? true else { return }
            lastProgressSaveAt[contentKey] = now

            guard let download = cachedDownload(forKey: contentKey) else { return }
            // The in-flight task only knows about its own byte range, so both counters
            // are offset by whatever was already on disk when this segment started.
            let base = segmentBaseBytes[contentKey] ?? 0
            download.bytesReceived = base + totalBytesWritten
            // Stays 0 when the server sends no Content-Length, which the UI renders as
            // an indeterminate bar rather than a progress bar frozen at 0%.
            if totalBytesExpectedToWrite > 0 {
                download.bytesExpected = base + totalBytesExpectedToWrite
            }
            try? modelContext.save()
        }
    }

    public nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        MainActor.assumeIsolated {
            guard let error, let contentKey = task.taskDescription else { return }
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled {
                return // explicit pause/cancel already handled its own state transition
            }
            guard let download = cachedDownload(forKey: contentKey) else { return }
            tasksByContentKey[contentKey] = nil

            // A dropped connection mid-file is the normal case with these panels, not a
            // dead end: whatever landed on disk is kept and the next segment resumes.
            let onDisk = bytesOnDisk(for: contentKey)
            download.bytesReceived = onDisk
            continueOrFail(
                download,
                madeProgress: onDisk > (segmentBaseBytes[contentKey] ?? 0),
                underlyingError: error.localizedDescription
            )
        }
    }

}

private extension DownloadManager {
    /// Requests the next byte range, unless the server has stopped making progress or
    /// the attempt budget is spent — in which case this fails loudly rather than
    /// spinning forever or leaving a truncated file looking "downloaded".
    func continueOrFail(
        _ download: Download,
        madeProgress: Bool,
        underlyingError: String? = nil
    ) {
        let contentKey = download.contentKey
        let attempts = (segmentAttempts[contentKey] ?? 0) + 1
        segmentAttempts[contentKey] = attempts

        guard madeProgress else {
            try? FileManager.default.removeItem(at: partFileURL(for: contentKey))
            fail(download, message: underlyingError
                ?? "The server stopped sending data and doesn't support resuming — this stream can't be downloaded.")
            return
        }
        guard attempts < Self.maximumSegmentAttempts else {
            fail(download, message: "Gave up after \(attempts) reconnects — the server keeps interrupting the transfer.")
            return
        }
        // Shown in the Downloads row while still in `.downloading`, so a transfer that
        // is limping along via reconnects is visibly different from a healthy one.
        download.lastError = "Server closed the connection — reconnect \(attempts)"
        try? modelContext?.save()
        startSegment(for: download)
    }
}
