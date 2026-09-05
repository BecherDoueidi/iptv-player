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

    @State private var controller = VLCPlaybackController()
    @State private var controlsVisible = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var showNextEpisodePrompt = false
    @State private var isScrubbing = false
    @State private var scrubSeconds: Double = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VLCVideoSurface(controller: controller).ignoresSafeArea()

            if controller.isBuffering && controller.errorMessage == nil {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.4)
            }

            if controlsVisible && controller.errorMessage == nil {
                controlsOverlay.transition(.opacity)
            }

            if let error = controller.errorMessage {
                errorOverlay(error)
            }

            if showNextEpisodePrompt, let onRequestNextEpisode {
                nextEpisodeOverlay(onRequestNextEpisode)
            }
        }
        .statusBarHidden()
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { controlsVisible.toggle() }
            scheduleAutoHide()
        }
        .task {
            controller.onProgress = { position, duration in
                // A live stream has no position worth remembering.
                guard !request.isLive else { return }
                saveProgress(position: position, duration: duration)
            }
            controller.onFinished = { handleFinished() }
            controller.start(url: request.url, resumeAt: request.isLive ? 0 : resumePosition())
            scheduleAutoHide()
        }
        .onDisappear {
            hideControlsTask?.cancel()
            controller.stop()
        }
    }

    // MARK: - Controls

    private var controlsOverlay: some View {
        VStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.6))
                }

                Spacer()

                Text(request.title)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                // Keeps the title visually centered against the close button.
                Color.clear.frame(width: 28, height: 28)
            }
            .padding()

            Spacer()

            HStack(spacing: 44) {
                if !request.isLive {
                    Button {
                        controller.skip(by: -10)
                        scheduleAutoHide()
                    } label: {
                        Image(systemName: "gobackward.10").font(.system(size: 32))
                    }
                }

                Button {
                    controller.togglePlayPause()
                    scheduleAutoHide()
                } label: {
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 44))
                }

                if !request.isLive {
                    Button {
                        controller.skip(by: 10)
                        scheduleAutoHide()
                    } label: {
                        Image(systemName: "goforward.10").font(.system(size: 32))
                    }
                }
            }
            .foregroundStyle(.white)

            Spacer()

            if request.isLive {
                liveIndicator
            } else {
            VStack(spacing: 2) {
                Slider(
                    value: Binding(
                        get: { isScrubbing ? scrubSeconds : controller.positionSeconds },
                        set: { scrubSeconds = $0 }
                    ),
                    in: 0...max(controller.durationSeconds, 1),
                    onEditingChanged: { editing in
                        if editing {
                            isScrubbing = true
                            controller.isScrubbingExternally = true
                            scrubSeconds = controller.positionSeconds
                        } else {
                            controller.seek(to: scrubSeconds)
                            isScrubbing = false
                            controller.isScrubbingExternally = false
                        }
                        scheduleAutoHide()
                    }
                )
                .tint(.white)

                HStack {
                    Text(timeLabel(isScrubbing ? scrubSeconds : controller.positionSeconds))
                    Spacer()
                    Text(timeLabel(controller.durationSeconds))
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            }
        }
        .background(
            LinearGradient(
                colors: [.black.opacity(0.55), .clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        )
    }

    private var liveIndicator: some View {
        HStack(spacing: 6) {
            Circle().fill(.red).frame(width: 8, height: 8)
            Text("LIVE").font(.caption).bold().foregroundStyle(.white)
        }
        .padding(.bottom, 12)
    }

    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.yellow)
            Text("Unable to play this stream")
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
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

    private func nextEpisodeOverlay(_ playNext: @escaping () -> Void) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    playNext()
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

    // MARK: - Helpers

    private func scheduleAutoHide() {
        hideControlsTask?.cancel()
        guard controlsVisible else { return }
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            // Only hide while actually playing — leaving the close button on screen
            // when paused or stalled means there's always a way out.
            guard controller.isPlaying else { return }
            withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = false }
        }
    }

    private func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    /// Host + path with the username/password path segments blanked out — shown in
    /// the error overlay so a failure is diagnosable instead of a dead end.
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
