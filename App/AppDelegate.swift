import UIKit
import IPTVCore

/// Bridges UIKit app-lifecycle events that SwiftUI's `App` protocol has no hook for.
/// The only reason this class exists is `handleEventsForBackgroundURLSession`, which
/// the OS calls to relaunch the app after a background download finishes.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Set once by AppDependencies at startup. A plain static var isn't ideal DI, but
    /// this is the one place UIKit forces a global reachability point onto an
    /// otherwise DI-container-based app — acceptable for a personal app's single
    /// instance. (Known edge case: if this delegate method fires before AppDependencies
    /// has finished constructing on a cold background-relaunch, the completion handler
    /// is simply never captured/called — the download's own delegate callbacks still
    /// fire correctly against the session either way, so this only risks the OS
    /// slightly overextending background execution time, not losing any download.)
    static var downloadManager: DownloadManager?

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        Self.downloadManager?.handleBackgroundEvents(completionHandler: completionHandler)
    }
}
