import SwiftUI

@main
struct IPTVPlayerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appDependencies, dependencies)
                .task {
                    dependencies.configureDownloadManagerIfNeeded()
                }
        }
        .modelContainer(dependencies.modelContainer)
    }
}
