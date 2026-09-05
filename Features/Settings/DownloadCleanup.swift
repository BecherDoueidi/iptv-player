import Foundation
import SwiftData
import IPTVCore

/// Opportunistic, foreground-triggered cleanup — not BGTaskScheduler-based.
/// Background app refresh is unreliable even for paid App Store apps, doubly so for
/// a free-signed sideloaded app that isn't launched often; running this at every
/// foreground/launch is the honest, reliable alternative.
enum DownloadCleanup {
    @MainActor
    static func run(modelContext: ModelContext, downloadManager: DownloadManager) {
        let policyRaw = UserDefaults.standard.string(forKey: "autoDeleteWatchedDownloads") ?? AutoDeletePolicy.never.rawValue
        guard let policy = AutoDeletePolicy(rawValue: policyRaw), let thresholdDays = policy.thresholdDays else { return }

        guard let downloads = try? modelContext.fetch(
            FetchDescriptor<Download>(predicate: #Predicate { $0.stateRaw == "completed" })
        ) else { return }
        guard let allProgress = try? modelContext.fetch(FetchDescriptor<WatchProgress>()) else { return }
        let progressByKey = Dictionary(uniqueKeysWithValues: allProgress.map { ($0.contentKey, $0) })

        let cutoff = Calendar.current.date(byAdding: .day, value: -thresholdDays, to: .now) ?? .now

        for download in downloads {
            guard let progress = progressByKey[download.contentKey],
                  progress.isCompleted,
                  progress.lastPlayedAt < cutoff
            else { continue }
            downloadManager.cancel(contentKey: download.contentKey)
        }
    }
}
