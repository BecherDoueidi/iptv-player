import UIKit

/// Bridges UIKit app-lifecycle events that SwiftUI's `App` protocol has no hook for.
/// The only reason this class exists is `handleEventsForBackgroundURLSession`, which
/// the OS calls to relaunch the app after a background download finishes — wired up
/// for real in Phase 6 (DownloadEngine). Kept as an explicit stub from Phase 0 onward
/// so the plumbing is proven to compile/run before it carries any real logic.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        // Phase 6 will stash this handler, recreate the background URLSession with
        // `identifier`, and call the handler once pending delegate callbacks finish.
        completionHandler()
    }
}
