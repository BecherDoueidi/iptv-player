import SwiftUI
import SwiftData
import UIKit
import IPTVCore

/// Keeps downloads alive across the two everyday interruptions that would otherwise
/// stop them dead: the screen locking, and briefly switching to another app.
///
/// Neither is true background downloading — iOS only offers that through a background
/// `URLSession`, which is exactly what these panels cut off after a few kilobytes, and
/// which can't stream chunks to disk the way the working engine does (background
/// sessions support only upload/download tasks, not data tasks). What this buys is
/// real but bounded: leave the phone alone and the transfer keeps going; tab away and
/// it survives the OS's grace period (typically ~30s) before being suspended. Anything
/// longer resumes from the `.part` file on return.
struct DownloadActivityModifier: ViewModifier {
    @Query(filter: #Predicate<Download> { $0.stateRaw == "downloading" })
    private var activeDownloads: [Download]

    @Environment(\.scenePhase) private var scenePhase
    @State private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private var isDownloading: Bool { !activeDownloads.isEmpty }

    func body(content: Content) -> some View {
        content
            .onChange(of: isDownloading, initial: true) { _, downloading in
                // Without this the screen locks, the app suspends, and the transfer
                // stops — the single most likely way to lose a long download.
                UIApplication.shared.isIdleTimerDisabled = downloading
                if !downloading { endBackgroundTask() }
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .background:
                    if isDownloading { beginBackgroundTask() }
                case .active:
                    endBackgroundTask()
                default:
                    break
                }
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
                endBackgroundTask()
            }
    }

    private func beginBackgroundTask() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "ActiveDownloads") {
            // Expiration handler: the OS is out of patience. Ending the assertion
            // cleanly avoids being killed outright; the partial file is already on
            // disk, so the download resumes on next foreground.
            endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
}

extension View {
    func keepsDownloadsRunning() -> some View {
        modifier(DownloadActivityModifier())
    }
}
