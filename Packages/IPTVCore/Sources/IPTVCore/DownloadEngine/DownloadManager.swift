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
/// Transfers are *segmented and streamed straight to disk*. These panels close the
/// connection every few dozen megabytes, so bytes are appended to a `.part` file as
/// they arrive and the next segment is requested with `Range: bytes=<offset>-`. The
/// file on disk is therefore always an accurate record of what has been received —
/// which is what makes a dropped connection cost nothing but a reconnect.
@MainActor
public final class DownloadManager: NSObject {
    private static let minimumValidFileSizeBytes: Int64 = 100_000 // sanity floor, not a real size estimate
    private static let minimumFreeDiskSpaceBytes: Int64 = 200_000_000 // 200 MB safety margin
    /// Generous, because a panel that cuts off every ~25 MB needs dozens of reconnects
    /// for one episode — but bounded, so a server that will never serve the whole file
    /// fails visibly instead of retrying forever.
    private static let maximumSegmentAttempts = 500
    /// A run of attempts that transfer nothing at all is the real "can't download this"
    /// signal; any single one of them could just be a transient network drop.
    private static let maximumEmptyAttempts = 6
    private static let reconnectDelaySeconds: Double = 0.75
    private static let emptyAttemptBackoffSeconds: Double = 3
    /// Sent because some panels truncate or refuse transfers for unrecognised clients.
    private static let playerUserAgent = "VLC/3.0.20 LibVLC/3.0.20"
    /// Statuses these panels return when they're temporarily unwilling rather than
    /// permanently unable — most importantly the bare 404 used for "too many
    /// connections on this account".
    private static let retryableStatusCodes: Set<Int> = [403, 404, 408, 429, 500, 502, 503, 504]

    private var session: URLSession!
    private var modelContext: ModelContext?
    private var tasksByContentKey: [String: URLSessionDataTask] = [:]
    private var lastProgressSaveAt: [String: Date] = [:]
    /// Avoids a SwiftData fetch inside the per-chunk callback, which fires many times
    /// per second — a query per callback on the main thread was starving the transfer.
    private var downloadsByContentKey: [String: Download] = [:]
    /// Open append handle on the `.part` file for each in-flight transfer.
    private var partHandles: [String: FileHandle] = [:]
    /// Bytes already on disk when the in-flight segment started, so the segment's own
    /// progress can be reported as progress through the whole file.
    private var segmentBaseBytes: [String: Int64] = [:]
    private var segmentAttempts: [String: Int] = [:]
    private var consecutiveEmptyAttempts: [String: Int] = [:]
    /// Pending backoff timers between segments, cancellable so a pause or delete takes
    /// effect immediately instead of firing a reconnect afterwards.
    private var retryTasks: [String: Task<Void, Never>] = [:]
    /// Set when a segment is deliberately stopped, so its `didCompleteWithError` isn't
    /// mistaken for the server dropping the connection.
    private var intentionallyStopped: Set<String> = []

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
        // transfer is affordable because segments resume from the `.part` file: a
        // download interrupted by backgrounding simply continues on next launch.
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60 * 60 * 12
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    /// Must be called once at app launch before enqueueing anything.
    public func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        reconcile()
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
        resetAttemptCounters(for: contentKey)
        try? modelContext.save()

        startSegment(for: download)
    }

    public func pause(contentKey: String) {
        guard let download = cachedDownload(forKey: contentKey) else { return }
        stopSegment(contentKey: contentKey)
        download.bytesReceived = bytesOnDisk(for: contentKey)
        download.state = .paused
        download.lastError = nil
        try? modelContext?.save()
    }

    public func resume(contentKey: String) {
        guard let download = cachedDownload(forKey: contentKey) else { return }
        resetAttemptCounters(for: contentKey)
        download.lastError = nil
        startSegment(for: download)
    }

    public func retry(contentKey: String) {
        resume(contentKey: contentKey)
    }

    /// Called when the app returns to the foreground. Transfers only run while the app
    /// is active (see `init`), so anything left mid-flight is picked up here —
    /// continuing from the `.part` file rather than restarting.
    public func resumeInterruptedDownloads() {
        guard let modelContext else { return }
        guard let downloads = try? modelContext.fetch(FetchDescriptor<Download>()) else { return }
        for download in downloads where download.state == .downloading || download.state == .queued {
            guard tasksByContentKey[download.contentKey] == nil else { continue }
            downloadsByContentKey[download.contentKey] = download
            resetAttemptCounters(for: download.contentKey)
            startSegment(for: download)
        }
    }

    public func cancel(contentKey: String) {
        guard let modelContext else { return }
        stopSegment(contentKey: contentKey)

        guard let download = cachedDownload(forKey: contentKey) else { return }
        if let fileURL = download.localFileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        try? FileManager.default.removeItem(at: partFileURL(for: contentKey))
        downloadsByContentKey[contentKey] = nil
        lastProgressSaveAt[contentKey] = nil
        segmentBaseBytes[contentKey] = nil
        segmentAttempts[contentKey] = nil
        consecutiveEmptyAttempts[contentKey] = nil
        modelContext.delete(download)
        try? modelContext.save()
    }

    // MARK: - Files

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

    private func resetAttemptCounters(for contentKey: String) {
        segmentAttempts[contentKey] = 0
        consecutiveEmptyAttempts[contentKey] = 0
    }

    private func closeHandle(for contentKey: String) {
        try? partHandles[contentKey]?.close()
        partHandles[contentKey] = nil
    }

    /// Cancels the in-flight segment without treating the resulting error as a server
    /// drop. Bytes already written to the `.part` file are kept.
    private func stopSegment(contentKey: String) {
        retryTasks[contentKey]?.cancel()
        retryTasks[contentKey] = nil
        if tasksByContentKey[contentKey] != nil {
            intentionallyStopped.insert(contentKey)
        }
        tasksByContentKey[contentKey]?.cancel()
        tasksByContentKey[contentKey] = nil
        closeHandle(for: contentKey)
    }

    // MARK: - Transfer

    /// Starts (or continues) a transfer, requesting only the bytes not already on disk.
    private func startSegment(for download: Download) {
        guard let url = URL(string: download.sourceStreamURLString) else {
            fail(download, message: "The stream address is no longer valid.")
            return
        }

        let contentKey = download.contentKey
        stopSegment(contentKey: contentKey)
        let offset = bytesOnDisk(for: contentKey)

        var request = URLRequest(url: url)
        request.setValue(Self.playerUserAgent, forHTTPHeaderField: "User-Agent")
        if offset > 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }

        let task = session.dataTask(with: request)
        task.taskDescription = contentKey
        tasksByContentKey[contentKey] = task
        segmentBaseBytes[contentKey] = offset
        download.bytesReceived = offset
        download.state = .downloading
        try? modelContext?.save()
        task.resume()
    }

    private func fail(_ download: Download, message: String) {
        stopSegment(contentKey: download.contentKey)
        download.state = .failed
        download.lastError = message
        try? modelContext?.save()
    }

    /// Opens (creating if needed) the append handle for a transfer's partial file.
    private func openHandle(for contentKey: String, truncating: Bool) -> FileHandle? {
        closeHandle(for: contentKey)
        let partURL = partFileURL(for: contentKey)
        if truncating || !FileManager.default.fileExists(atPath: partURL.path) {
            FileManager.default.createFile(atPath: partURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: partURL) else { return nil }
        try? handle.seekToEnd()
        partHandles[contentKey] = handle
        return handle
    }

    private func finish(_ download: Download) {
        guard let modelContext else { return }
        let contentKey = download.contentKey
        stopSegment(contentKey: contentKey)

        let partURL = partFileURL(for: contentKey)
        let totalBytes = bytesOnDisk(for: contentKey)

        guard totalBytes > Self.minimumValidFileSizeBytes else {
            try? FileManager.default.removeItem(at: partURL)
            let size = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            fail(download, message: "The server sent only \(size) — this stream doesn't appear to allow downloading.")
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

    /// Brings persisted rows back in line with reality at launch, so the UI never shows
    /// a stale "downloading" state. Partial files are kept: anything interrupted is left
    /// as `.downloading` for `resumeInterruptedDownloads()` to continue.
    private func reconcile() {
        guard let modelContext else { return }
        guard let downloads = try? modelContext.fetch(FetchDescriptor<Download>()) else { return }

        for download in downloads {
            downloadsByContentKey[download.contentKey] = download
            switch download.state {
            case .downloading, .queued:
                if let fileURL = download.localFileURL, FileManager.default.fileExists(atPath: fileURL.path) {
                    download.state = .completed
                } else {
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

extension DownloadManager: URLSessionDataDelegate {
    public nonisolated func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        MainActor.assumeIsolated {
            guard let contentKey = dataTask.taskDescription,
                  let download = cachedDownload(forKey: contentKey) else {
                completionHandler(.cancel)
                return
            }

            let http = response as? HTTPURLResponse
            if let http, !(200...299).contains(http.statusCode) {
                completionHandler(.cancel)
                // Claim the resulting cancellation so `didCompleteWithError` doesn't
                // also treat it as a dropped connection and retry a second time.
                intentionallyStopped.insert(contentKey)
                tasksByContentKey[contentKey] = nil
                // Panels cap concurrent connections per account and answer a request
                // over that cap with an outright 404/403 rather than anything
                // descriptive. Since the connection we just dropped may not have been
                // released server-side yet, a refusal part-way through a file is worth
                // retrying (with backoff) instead of condemning the download.
                let refusedMidTransfer = Self.retryableStatusCodes.contains(http.statusCode)
                    && bytesOnDisk(for: contentKey) > 0
                if refusedMidTransfer {
                    continueOrFail(
                        download,
                        madeProgress: false,
                        underlyingError: "The server refused the download (HTTP \(http.statusCode))."
                    )
                } else {
                    fail(download, message: "The server refused the download (HTTP \(http.statusCode)).")
                }
                return
            }

            let base = segmentBaseBytes[contentKey] ?? 0
            // 200 in reply to a `Range` request means the server ignored it and is
            // resending from byte zero. Appending that would duplicate bytes and corrupt
            // the file, so the partial is discarded and this response replaces it.
            let rangeIgnored = base > 0 && http?.statusCode == 200
            if rangeIgnored {
                segmentBaseBytes[contentKey] = 0
            }

            guard openHandle(for: contentKey, truncating: rangeIgnored) != nil else {
                completionHandler(.cancel)
                fail(download, message: "Couldn't write to storage.")
                return
            }

            let offset = segmentBaseBytes[contentKey] ?? 0
            if response.expectedContentLength > 0 {
                download.bytesExpected = offset + response.expectedContentLength
            }
            download.bytesReceived = offset
            try? modelContext?.save()
            completionHandler(.allow)
        }
    }

    public nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        MainActor.assumeIsolated {
            guard let contentKey = dataTask.taskDescription,
                  let handle = partHandles[contentKey],
                  let modelContext else { return }

            // Written the moment it arrives. This is the whole point of the redesign:
            // the `.part` file is always an accurate record of what has been received,
            // so a connection dropped mid-segment costs a reconnect and nothing else.
            do {
                try handle.write(contentsOf: data)
            } catch {
                guard let download = cachedDownload(forKey: contentKey) else { return }
                fail(download, message: error.localizedDescription)
                return
            }

            // Throttle the *model mutation itself*, not just the save. Every mutation
            // makes SwiftData notify each @Query observing Download — which re-renders
            // whole episode lists on the main thread, starving the very callbacks
            // driving the transfer. Once per second is plenty for a progress bar.
            let now = Date()
            guard lastProgressSaveAt[contentKey].map({ now.timeIntervalSince($0) >= 1 }) ?? true else { return }
            lastProgressSaveAt[contentKey] = now

            guard let download = cachedDownload(forKey: contentKey) else { return }
            download.bytesReceived = (try? handle.offset()).map(Int64.init) ?? download.bytesReceived
            try? modelContext.save()
        }
    }

    public nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        MainActor.assumeIsolated {
            guard let contentKey = task.taskDescription else { return }

            if intentionallyStopped.remove(contentKey) != nil { return }
            guard let download = cachedDownload(forKey: contentKey) else { return }

            closeHandle(for: contentKey)
            tasksByContentKey[contentKey] = nil

            let base = segmentBaseBytes[contentKey] ?? 0
            let onDisk = bytesOnDisk(for: contentKey)
            download.bytesReceived = onDisk

            if download.state == .failed { return } // already reported a hard failure

            let expected = download.bytesExpected
            // No error *and* nothing more expected means the file is complete. A clean
            // close short of `Content-Length` is the panel cutting us off, which the
            // next ranged segment picks up from.
            if error == nil, expected <= 0 || onDisk >= expected {
                finish(download)
                return
            }

            continueOrFail(
                download,
                madeProgress: onDisk > base,
                underlyingError: error?.localizedDescription
            )
        }
    }
}

private extension DownloadManager {
    /// Requests the next byte range, unless the server has stopped sending anything at
    /// all or the attempt budget is spent — in which case this fails loudly rather than
    /// spinning forever or leaving a truncated file looking "downloaded".
    func continueOrFail(
        _ download: Download,
        madeProgress: Bool,
        underlyingError: String? = nil
    ) {
        let contentKey = download.contentKey
        let attempts = (segmentAttempts[contentKey] ?? 0) + 1
        segmentAttempts[contentKey] = attempts

        // A single fruitless attempt isn't proof the stream can't be downloaded — a
        // transient network drop looks identical. Only a run of them is conclusive.
        let barren = madeProgress ? 0 : (consecutiveEmptyAttempts[contentKey] ?? 0) + 1
        consecutiveEmptyAttempts[contentKey] = barren
        guard barren < Self.maximumEmptyAttempts else {
            // The partial file is deliberately left in place, so Retry picks up from
            // wherever it got to rather than starting over.
            fail(download, message: underlyingError
                ?? "The server stopped sending data — this stream can't be downloaded.")
            return
        }
        guard attempts < Self.maximumSegmentAttempts else {
            fail(download, message: "Gave up after \(attempts) reconnects — the server keeps interrupting the transfer.")
            return
        }

        // Reconnecting instantly is what trips a panel's per-account connection cap:
        // the socket we just lost may not be released server-side yet, and the panel
        // answers the replacement request with a bare 404. Backing off — harder after
        // an attempt that transferred nothing — gives it time to let go.
        // A drop right after a healthy chunk is this server's normal behaviour and needs
        // only a brief pause for the socket to be released — waiting the full backoff
        // there added minutes of dead time across the ~90 reconnects one file takes.
        // The long backoff is for attempts that transferred nothing, where the account's
        // connection cap is the likely cause.
        let delay = madeProgress
            ? Self.reconnectDelaySeconds
            : Self.emptyAttemptBackoffSeconds * Double(barren)
        download.lastError = "\(underlyingError ?? "Connection dropped") Reconnecting (\(attempts))…"
        download.state = .downloading
        try? modelContext?.save()

        let contentKeyForRetry = contentKey
        retryTasks[contentKey]?.cancel()
        retryTasks[contentKey] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.retryTasks[contentKeyForRetry] = nil
            // The user may have paused, cancelled or deleted it while we waited.
            guard let current = self.cachedDownload(forKey: contentKeyForRetry),
                  current.state == .downloading else { return }
            self.startSegment(for: current)
        }
    }
}
