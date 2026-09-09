import SwiftUI
import SwiftData
import IPTVCore

struct DownloadsListView: View {
    let dependencies: AppDependencies

    @Query(sort: \Download.createdAt, order: .reverse) private var downloads: [Download]
    @Environment(\.modelContext) private var modelContext
    @State private var playbackRequest: PlaybackRequest?

    var body: some View {
        NavigationStack {
            Group {
                if downloads.isEmpty {
                    ContentUnavailableView(
                        "No downloads yet",
                        systemImage: "arrow.down.circle",
                        description: Text("Download a movie or episode to watch it offline.")
                    )
                } else {
                    List {
                        ForEach(downloads) { download in
                            DownloadRow(
                                download: download,
                                dependencies: dependencies,
                                onPlay: { playbackRequest = $0 }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Downloads")
            .fullScreenCover(item: $playbackRequest) { request in
                PlayerScreen(request: request)
            }
        }
    }
}

private struct DownloadRow: View {
    let download: Download
    let dependencies: AppDependencies
    let onPlay: (PlaybackRequest) -> Void

    @State private var showingDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if download.state == .completed {
                    Button {
                        play()
                    } label: {
                        HStack {
                            Text(download.title).font(.headline)
                            Spacer()
                            Image(systemName: "play.circle").foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(download.title).font(.headline)
                }
            }

            switch download.state {
            case .downloading:
                if download.bytesExpected > 0 {
                    ProgressView(value: progressFraction)
                    Text("\(formattedBytes(download.bytesReceived)) / \(formattedBytes(download.bytesExpected))\(rateAndETA)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    // No Content-Length from the server — an indeterminate bar is
                    // honest here, where a 0%-forever progress bar looks broken.
                    ProgressView()
                    Text("\(formattedBytes(download.bytesReceived)) downloaded\(rateAndETA)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // Non-fatal note while still downloading — surfaces a transfer that is
                // only limping along by reconnecting after each server cut-off.
                if let note = download.lastError {
                    Text(note).font(.caption2).foregroundStyle(.orange)
                }
            case .paused:
                Text("Paused — \(formattedBytes(download.bytesReceived)) downloaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .queued:
                // Downloads run one at a time on purpose — see maximumConcurrentTransfers.
                Text("Waiting for the current download to finish")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .completed:
                Text("Downloaded — \(formattedBytes(download.bytesReceived))")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .failed:
                Text(download.lastError ?? "Failed").font(.caption).foregroundStyle(.red)
            case .waitingForConnection:
                // Not an error: the account's connections are all in use, most likely
                // by another device, and this will start itself when one frees up.
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Waiting for a free connection")
                }
                .font(.caption)
                .foregroundStyle(.orange)
                if download.bytesReceived > 0 {
                    Text("\(formattedBytes(download.bytesReceived)) downloaded so far")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case .cancelled:
                Text("Cancelled").font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                switch download.state {
                case .downloading:
                    Button("Pause") {
                        dependencies.downloadManager.pause(contentKey: download.contentKey)
                    }
                case .paused:
                    Button("Resume") {
                        dependencies.downloadManager.resume(contentKey: download.contentKey)
                    }
                case .failed:
                    Button("Retry") {
                        dependencies.downloadManager.retry(contentKey: download.contentKey)
                    }
                case .waitingForConnection:
                    Button("Try Now") {
                        dependencies.downloadManager.resume(contentKey: download.contentKey)
                    }
                case .queued, .completed, .cancelled:
                    EmptyView()
                }

                Spacer()

                Button("Delete", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                dependencies.downloadManager.cancel(contentKey: download.contentKey)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteConfirmationMessage)
        }
    }

    /// Deleting is irreversible and re-downloading is expensive on these panels, so the
    /// wording says which of the two very different things this button is about to do.
    private var deleteConfirmationTitle: String {
        download.state == .completed ? "Delete \(download.title)?" : "Stop downloading \(download.title)?"
    }

    private var deleteConfirmationMessage: String {
        switch download.state {
        case .completed:
            return "This removes the downloaded file from your device. You can download it again later."
        case .downloading, .queued, .paused, .waitingForConnection:
            return "This cancels the download and discards the \(formattedBytes(download.bytesReceived)) already downloaded."
        case .failed, .cancelled:
            return "This removes it from the list, along with any partly downloaded file."
        }
    }

    private func play() {
        guard let localURL = download.localFileURL else { return }
        onPlay(PlaybackRequest(url: localURL, title: download.title, contentKey: download.contentKey))
    }

    /// Empty until a rate is actually known, so the label never claims "0 KB/s" for a
    /// transfer that simply hasn't been sampled yet.
    private var rateAndETA: String {
        let rate = download.bytesPerSecond
        guard rate > 1 else { return "" }
        var text = " · \(formattedBytes(Int64(rate)))/s"
        let remaining = download.bytesExpected - download.bytesReceived
        if download.bytesExpected > 0, remaining > 0 {
            text += " · \(formattedDuration(Double(remaining) / rate)) left"
        }
        return text
    }

    private func formattedDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "—" }
        let total = Int(seconds)
        if total < 60 { return "\(total)s" }
        if total < 3600 { return "\(total / 60)m" }
        return "\(total / 3600)h \((total % 3600) / 60)m"
    }

    private var progressFraction: Double {
        download.bytesExpected > 0 ? Double(download.bytesReceived) / Double(download.bytesExpected) : 0
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
