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
    @AppStorage("autoplayNextEpisode") private var autoplayNextEpisode = false
    @State private var showNextEpisodePrompt = false
    @State private var playbackErrorMessage: String?
    @State private var closeButtonVisible = true
    @State private var hideCloseButtonTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            PlayerViewControllerRepresentable(
                url: request.url,
                initialPosition: resumePosition(),
                onProgress: saveProgress,
                onFinished: handleFinished,
                onError: { playbackErrorMessage = $0 }
            )
            .ignoresSafeArea()

            if closeButtonVisible {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.6))
                        .padding()
                }
                .transition(.opacity)
            }

            if let playbackErrorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)
                    Text("Unable to play this stream")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(playbackErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Text(redactedURLDescription)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Close") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(32)
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
        // `.simultaneousGesture` (not `.onTapGesture`) so this doesn't steal the tap
        // from AVPlayerViewController's own tap-to-reveal-controls gesture underneath —
        // both fire together.
        .simultaneousGesture(
            TapGesture().onEnded {
                withAnimation(.easeInOut(duration: 0.2)) {
                    closeButtonVisible.toggle()
                }
                scheduleAutoHideCloseButton()
            }
        )
        .onAppear {
            scheduleAutoHideCloseButton()
        }
    }

    private func scheduleAutoHideCloseButton() {
        hideCloseButtonTask?.cancel()
        guard closeButtonVisible else { return }
        hideCloseButtonTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                closeButtonVisible = false
            }
        }
    }

    /// Host + path with the username/password path segments blanked out — shown in
    /// the error overlay so a "cannot open" failure is actually diagnosable instead
    /// of a dead end.
    private var redactedURLDescription: String {
        guard var components = URLComponents(url: request.url, resolvingAgainstBaseURL: false) else {
            return request.url.absoluteString
        }
        var segments = components.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if segments.count >= 4 {
            segments[2] = "***"
            segments[3] = "***"
        }
        components.path = segments.joined(separator: "/")
        return components.url?.absoluteString ?? request.url.absoluteString
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
        guard let onRequestNextEpisode else { return }
        if autoplayNextEpisode {
            onRequestNextEpisode()
        } else {
            showNextEpisodePrompt = true
        }
    }
}
