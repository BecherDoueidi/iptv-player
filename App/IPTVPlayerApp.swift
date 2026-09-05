import SwiftUI

@main
struct IPTVPlayerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    private let dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appDependencies, dependencies)
                .task {
                    dependencies.configureDownloadManagerIfNeeded()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    // Opportunistic, not BGTaskScheduler-based — runs whenever the
                    // app actually comes to the foreground, since background
                    // refresh is unreliable even for paid App Store apps.
                    if newPhase == .active {
                        DownloadCleanup.run(
                            modelContext: dependencies.modelContainer.mainContext,
                            downloadManager: dependencies.downloadManager
                        )
                        // Transfers only run while the app is active, so anything left
                        // mid-flight continues here from its partial file.
                        dependencies.downloadManager.resumeInterruptedDownloads()
                    }
                }
        }
        .modelContainer(dependencies.modelContainer)
    }
}
