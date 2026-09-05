import SwiftUI
import UIKit

/// Bare UIView for VLC to render into — VLC draws directly into a host view rather
/// than providing its own view controller the way AVKit does.
struct VLCVideoSurface: UIViewRepresentable {
    let controller: VLCPlaybackController

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        // VLC only needs this view to render into — it must not accept touches, or it
        // swallows every tap before SwiftUI's gesture sees it, which left the player
        // with no way to re-show the controls once they auto-hid (force-quit territory).
        view.isUserInteractionEnabled = false
        controller.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
