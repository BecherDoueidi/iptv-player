import SwiftUI
import UIKit

/// Bare UIView for VLC to render into — VLC draws directly into a host view rather
/// than providing its own view controller the way AVKit does.
struct VLCVideoSurface: UIViewRepresentable {
    let controller: VLCPlaybackController

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        controller.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
