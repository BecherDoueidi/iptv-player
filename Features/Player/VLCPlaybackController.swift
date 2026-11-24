import Foundation
import Observation
import UIKit
import AVFoundation
import VLCKitSPM

/// VLC replaces AVPlayer entirely because AVFoundation cannot open Matroska (.mkv),
/// AVI, or raw TS containers — which is most of a typical Xtream catalog (confirmed
/// on-device: a .mkv episode failed with AVFoundation's "Cannot Open"). The cost is
/// losing AVPlayerViewController's free chrome (PiP, AirPlay, native transport
/// controls), so PlayerScreen builds its own controls on top of this.
///
/// Recovers from a dropped stream on its own. This panel cuts connections constantly —
/// it does so every ~25 MB during downloads — and making the user back out of the
/// player and re-enter just to resume is asking them to do by hand what the app can
/// do itself, from the position they were already at.
@MainActor
@Observable
final class VLCPlaybackController {
    private let player = VLCMediaPlayer()
    private var pollTimer: Timer?
    private var pendingResumeSeconds: TimeInterval = 0
    private var hasAppliedResume = false
    private var hasReportedFinish = false
    private var hasStartedPlayback = false
    private var lastProgressReportAt = Date.distantPast
    private var startedAt = Date.distantPast

    /// What is playing, kept so a recovery attempt can reopen it.
    private var sourceURL: URL?
    private var isLiveStream = false

    /// Stall detection: position in milliseconds and when it last actually moved.
    private var lastObservedMilliseconds: Double = -1
    private var lastMovementAt = Date.distantPast
    private var isPausedByUser = false

    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?

    /// VLC will sit on a dead URL indefinitely without reporting `.error`, which is
    /// how a stream the panel refuses turns into a spinner that never resolves.
    private static let startTimeoutSeconds: TimeInterval = 25
    /// Playback that has been running and then stops advancing is a dropped
    /// connection. Generous enough not to fire on an ordinary rebuffer.
    private static let stallTimeoutSeconds: TimeInterval = 12
    private static let maximumReconnectAttempts = 5
    /// The panel often hasn't released the old connection yet, and on a
    /// one-connection account reconnecting instantly just gets refused.
    private static let reconnectDelaySeconds: TimeInterval = 3

    private(set) var positionSeconds: Double = 0
    private(set) var durationSeconds: Double = 0
    private(set) var isPlaying = false
    private(set) var isBuffering = true
    private(set) var errorMessage: String?
    /// Drives the "Reconnecting…" overlay; nil when playback is healthy.
    private(set) var reconnectStatus: String?

    var onProgress: ((TimeInterval, TimeInterval) -> Void)?
    var onFinished: (() -> Void)?

    /// `nonisolated` so a SwiftUI `@State` default value can construct it — same
    /// reasoning as DownloadManager's init.
    nonisolated init() {}

    func attach(to view: UIView) {
        player.drawable = view
    }

    func start(url: URL, resumeAt seconds: TimeInterval, isLive: Bool = false) {
        sourceURL = url
        isLiveStream = isLive
        pendingResumeSeconds = seconds
        configureAudioSession()
        openStream()
        startPolling()
    }

    /// Reopens the current stream from the top of the pipeline. Used both by automatic
    /// recovery and by the Try Again button.
    func retryNow() {
        reconnectTask?.cancel()
        reconnectAttempt = 0
        errorMessage = nil
        reconnectStatus = nil
        // A live stream has no meaningful position to return to; a VOD title does.
        pendingResumeSeconds = isLiveStream ? 0 : positionSeconds
        hasAppliedResume = false
        openStream()
        startPolling()
    }

    func togglePlayPause() {
        if player.isPlaying {
            player.pause()
            isPlaying = false
            isPausedByUser = true
        } else {
            player.play()
            isPlaying = true
            isPausedByUser = false
            // Otherwise the time spent paused counts as a stall the moment we resume.
            lastMovementAt = Date()
        }
    }

    func skip(by seconds: Double) {
        guard durationSeconds > 0 else { return }
        seek(to: min(max(positionSeconds + seconds, 0), durationSeconds))
    }

    func seek(to seconds: Double) {
        guard durationSeconds > 0 else { return }
        // `position` (0...1 Float) rather than assigning `time` — it's readwrite in
        // every VLCKit version, so this is the lower-risk seeking API.
        player.position = Float(seconds / durationSeconds)
        positionSeconds = seconds
        lastMovementAt = Date()
    }

    func stop() {
        reconnectTask?.cancel()
        reconnectTask = nil
        pollTimer?.invalidate()
        pollTimer = nil
        // Flush a final progress update so closing mid-playback still saves position.
        if durationSeconds > 0, !hasReportedFinish {
            onProgress?(positionSeconds, durationSeconds)
        }
        player.stop()
    }

    // MARK: - Private

    private func openStream() {
        guard let sourceURL else { return }
        hasStartedPlayback = false
        isBuffering = true
        lastObservedMilliseconds = -1
        lastMovementAt = Date()
        isPausedByUser = false
        startedAt = Date()
        player.media = VLCMedia(url: sourceURL)
        player.play()
        isPlaying = true
    }

    private func configureAudioSession() {
        // AVPlayerViewController did this implicitly; with VLC we have to, or audio
        // gets silenced by the ring/silent switch.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func startPolling() {
        pollTimer?.invalidate()
        // Polling public properties rather than conforming to VLCMediaPlayerDelegate:
        // the delegate's Swift signatures vary across VLCKit versions, and there's no
        // local build here to verify against — a timer is far harder to get wrong.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func poll() {
        // The `as X?` casts keep this compiling regardless of whether VLCKit's ObjC
        // headers expose these as optional, implicitly-unwrapped, or non-optional.
        let currentMs = Double(((player.time as VLCTime?)?.intValue) ?? 0)
        let lengthMs = Double((((player.media as VLCMedia?)?.length as VLCTime?)?.intValue) ?? 0)

        if lengthMs > 0 {
            durationSeconds = lengthMs / 1000
        }
        if !isScrubbingExternally {
            positionSeconds = currentMs / 1000
        }
        isPlaying = player.isPlaying

        // VLCKit's `state` is unreliable for this — it frequently sits at `.buffering`
        // through normal playback (observed on-device: video playing fine behind a
        // spinner that never went away). Actual progress is the trustworthy signal.
        if player.isPlaying, currentMs > 0 {
            hasStartedPlayback = true
            // Budget is per outage, not per session: a stream that recovers and plays
            // again has earned a fresh set of attempts for the next drop. Otherwise a
            // long watch on a flaky panel exhausts the budget and dies mid-episode.
            if reconnectAttempt > 0 {
                reconnectAttempt = 0
            }
        }
        isBuffering = !hasStartedPlayback && reconnectStatus == nil

        if currentMs != lastObservedMilliseconds {
            lastObservedMilliseconds = currentMs
            lastMovementAt = Date()
        }

        if player.state == .error {
            beginRecovery(reason: "The stream dropped.")
            return
        }

        // Nothing has played after the timeout: the stream is not coming.
        if !hasStartedPlayback, Date().timeIntervalSince(startedAt) > Self.startTimeoutSeconds {
            beginRecovery(reason: "The stream didn't start.")
            return
        }

        // `.ended` plus a position-based fallback, since `state` can't be fully trusted.
        // Checked before the stall test: a finished title has legitimately stopped moving.
        let reachedEnd = durationSeconds > 0 && positionSeconds >= durationSeconds - 1
        if player.state == .ended || (hasStartedPlayback && reachedEnd) {
            guard !hasReportedFinish else { return }
            hasReportedFinish = true
            isBuffering = false
            onProgress?(durationSeconds, durationSeconds)
            onFinished?()
            return
        }

        // Was playing, then stopped advancing — a dropped connection, not an error VLC
        // reports. This is the case that used to force the user to back out and re-enter.
        if hasStartedPlayback, !isPausedByUser,
           Date().timeIntervalSince(lastMovementAt) > Self.stallTimeoutSeconds {
            beginRecovery(reason: "The stream stopped responding.")
            return
        }

        if !hasAppliedResume, pendingResumeSeconds > 0, durationSeconds > 0, player.isPlaying {
            hasAppliedResume = true
            seek(to: pendingResumeSeconds)
        }

        // Throttled to ~5s so watch progress isn't written to disk twice a second.
        if durationSeconds > 0, Date().timeIntervalSince(lastProgressReportAt) >= 5 {
            lastProgressReportAt = Date()
            onProgress?(positionSeconds, durationSeconds)
        }
    }

    /// Reopens the stream after a pause, keeping the user's place. Gives up with a
    /// readable message once the attempts are spent, rather than retrying forever.
    private func beginRecovery(reason: String) {
        stopPolling()
        reconnectAttempt += 1

        guard reconnectAttempt <= Self.maximumReconnectAttempts else {
            isBuffering = false
            reconnectStatus = nil
            errorMessage = "\(reason) Reconnecting didn't help after "
                + "\(Self.maximumReconnectAttempts) attempts — the server may not have this "
                + "title, or all your account's connections are in use."
            return
        }

        // Keep the user's place: a live stream resumes at the live edge, a VOD title
        // at the second it dropped.
        let resumeAt = isLiveStream ? 0 : positionSeconds
        reconnectStatus = "\(reason) Reconnecting… (\(reconnectAttempt)/\(Self.maximumReconnectAttempts))"
        player.stop()

        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(Self.reconnectDelaySeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.pendingResumeSeconds = resumeAt
            self.hasAppliedResume = false
            self.reconnectStatus = nil
            self.openStream()
            self.startPolling()
        }
    }

    /// Set by the scrubber so polling doesn't yank the slider back mid-drag.
    var isScrubbingExternally = false
}
