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
@MainActor
@Observable
final class VLCPlaybackController {
    private let player = VLCMediaPlayer()
    private var pollTimer: Timer?
    private var pendingResumeSeconds: TimeInterval = 0
    private var hasAppliedResume = false
    private var hasReportedFinish = false
    private var lastProgressReportAt = Date.distantPast

    private(set) var positionSeconds: Double = 0
    private(set) var durationSeconds: Double = 0
    private(set) var isPlaying = false
    private(set) var isBuffering = true
    private(set) var errorMessage: String?

    var onProgress: ((TimeInterval, TimeInterval) -> Void)?
    var onFinished: (() -> Void)?

    /// `nonisolated` so a SwiftUI `@State` default value can construct it — same
    /// reasoning as DownloadManager's init.
    nonisolated init() {}

    func attach(to view: UIView) {
        player.drawable = view
    }

    func start(url: URL, resumeAt seconds: TimeInterval) {
        pendingResumeSeconds = seconds
        configureAudioSession()
        player.media = VLCMedia(url: url)
        player.play()
        isPlaying = true
        startPolling()
    }

    func togglePlayPause() {
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
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
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        // Flush a final progress update so closing mid-playback still saves position.
        if durationSeconds > 0, !hasReportedFinish {
            onProgress?(positionSeconds, durationSeconds)
        }
        player.stop()
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

        switch player.state {
        case .error:
            errorMessage = "VLC couldn't open this stream."
            pollTimer?.invalidate()
            pollTimer = nil
            return
        case .ended:
            guard !hasReportedFinish else { return }
            hasReportedFinish = true
            isBuffering = false
            if durationSeconds > 0 {
                onProgress?(durationSeconds, durationSeconds)
            }
            onFinished?()
            return
        default:
            isBuffering = (player.state == .buffering || player.state == .opening)
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

    /// Set by the scrubber so polling doesn't yank the slider back mid-drag.
    var isScrubbingExternally = false
}
