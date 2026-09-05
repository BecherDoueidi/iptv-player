import SwiftUI
import SwiftData
import IPTVCore

struct PlayerScreen: View {
    let request: PlaybackRequest
    /// Non-nil when there's a next episode to offer — tapping "Next Episode" calls this
    /// so the owning view can swap in the next `PlaybackRequest`.
    var onRequestNextEpisode: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showNextEpisodePrompt = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            PlayerViewControllerRepresentable(
                url: request.url,
                initialPosition: resumePosition(),
                onProgress: saveProgress,
                onFinished: handleFinished
            )
            .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
                    .padding()
            }

            if showNextEpisodePrompt, let onRequestNextEpisode {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            onRequestNextEpisode()
                            showNextEpisodePrompt = false
                        } label: {
                            Label("Next Episode", systemImage: "forward.end.fill")
                                .padding()
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .padding()
                    }
                }
            }
        }
    }

    private func resumePosition() -> TimeInterval {
        let key = request.contentKey
        let descriptor = FetchDescriptor<WatchProgress>(predicate: #Predicate { $0.contentKey == key })
        guard let progress = try? modelContext.fetch(descriptor).first, !progress.isCompleted else { return 0 }
        return progress.positionSeconds
    }

    private func saveProgress(position: TimeInterval, duration: TimeInterval) {
        let key = request.contentKey
        let completed = WatchProgressPolicy.isCompleted(positionSeconds: position, durationSeconds: duration)
        let descriptor = FetchDescriptor<WatchProgress>(predicate: #Predicate { $0.contentKey == key })

        if let existing = try? modelContext.fetch(descriptor).first {
            existing.positionSeconds = position
            existing.durationSeconds = duration
            existing.lastPlayedAt = .now
            existing.isCompleted = completed
        } else {
            modelContext.insert(WatchProgress(
                contentKey: key,
                positionSeconds: position,
                durationSeconds: duration,
                isCompleted: completed
            ))
        }
        try? modelContext.save()
    }

    private func handleFinished() {
        if onRequestNextEpisode != nil {
            showNextEpisodePrompt = true
        }
    }
}
