import UIKit
import IPTVCore

/// Bridges UIKit app-lifecycle events that SwiftUI's `App` protocol has no hook for.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Set once by AppDependencies at startup. A plain static var isn't ideal DI, but
    /// this is the one place UIKit forces a global reachability point onto an
    /// otherwise DI-container-based app — acceptable for a personal app's single instance.
    static var downloadManager: DownloadManager?

    /// Only reachable from a leftover system-registered background session from an
    /// earlier build; the app now downloads through an in-process session (see
    /// `DownloadManager.init`). Calling the handler immediately keeps the OS from
    /// waiting on events that will never arrive.
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
