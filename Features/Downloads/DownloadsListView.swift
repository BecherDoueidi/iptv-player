import SwiftUI
import SwiftData
import IPTVCore

struct DownloadsListView: View {
    let dependencies: AppDependencies

    @Query(sort: \Download.createdAt, order: .reverse) private var downloads: [Download]
    @Environment(\.modelContext) private var modelContext

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
                            DownloadRow(download: download, dependencies: dependencies)
                        }
                    }
                }
            }
            .navigationTitle("Downloads")
        }
    }
}

private struct DownloadRow: View {
    let download: Download
    let dependencies: AppDependencies

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(download.title).font(.headline)

            switch download.state {
            case .downloading:
                ProgressView(value: progressFraction)
                Text("\(formattedBytes(download.bytesReceived)) / \(formattedBytes(download.bytesExpected))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .paused:
                Text("Paused — \(formattedBytes(download.bytesReceived)) downloaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .queued:
                Text("Queued").font(.caption).foregroundStyle(.secondary)
            case .completed:
                Text("Downloaded — \(formattedBytes(download.bytesReceived))")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .failed:
                Text(download.lastError ?? "Failed").font(.caption).foregroundStyle(.red)
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
                case .queued, .completed, .cancelled:
                    EmptyView()
                }

                Spacer()

                Button("Delete", role: .destructive) {
                    dependencies.downloadManager.cancel(contentKey: download.contentKey)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    private var progressFraction: Double {
        download.bytesExpected > 0 ? Double(download.bytesReceived) / Double(download.bytesExpected) : 0
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
