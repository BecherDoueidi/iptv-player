import SwiftUI
import AVKit

/// Wraps `AVPlayerViewController` directly (decision: not raw `AVPlayerLayer`, not
/// SwiftUI's plain `VideoPlayer`) — this gets PiP, AirPlay routing, and system
/// transport/subtitle-track-selection UI for free, while still giving direct access
/// to the underlying `AVPlayer` for resume-seek and progress observation.
struct PlayerViewControllerRepresentable: UIViewControllerRepresentable {
    let url: URL
    let initialPosition: TimeInterval
    let onProgress: (TimeInterval, TimeInterval) -> Void
    let onFinished: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onProgress: onProgress, onFinished: onFinished)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true

        if initialPosition > 0 {
            player.seek(to: CMTime(seconds: initialPosition, preferredTimescale: 600))
        }

        context.coordinator.timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 5, preferredTimescale: 1),
            queue: .main
        ) { [weak player] time in
            guard let duration = player?.currentItem?.duration.seconds, duration.isFinite, duration > 0 else { return }
            context.coordinator.onProgress(time.seconds, duration)
        }

        context.coordinator.finishObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            context.coordinator.onFinished()
        }

        player.play()
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        if let token = coordinator.timeObserverToken {
            uiViewController.player?.removeTimeObserver(token)
        }
        if let observer = coordinator.finishObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        uiViewController.player?.pause()
    }

    final class Coordinator {
        let onProgress: (TimeInterval, TimeInterval) -> Void
        let onFinished: () -> Void
        var timeObserverToken: Any?
        var finishObserver: NSObjectProtocol?

        init(onProgress: @escaping (TimeInterval, TimeInterval) -> Void, onFinished: @escaping () -> Void) {
            self.onProgress = onProgress
            self.onFinished = onFinished
        }
    }
}
