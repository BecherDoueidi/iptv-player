import SwiftUI
import AVKit

/// Wraps `AVPlayerViewController` directly (decision: not raw `AVPlayerLayer`, not
/// SwiftUI's plain `VideoPlayer`) — this gets PiP, AirPlay routing, and system
/// transport/subtitle-track-selection UI for free, while still giving Phase 5+
/// direct access to the underlying `AVPlayer` for resume-seek and progress observation.
struct PlayerViewControllerRepresentable: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = AVPlayer(url: url)
        controller.allowsPictureInPicturePlayback = true
        controller.player?.play()
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}
