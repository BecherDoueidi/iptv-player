import Foundation
import SwiftUI
import SwiftData
import IPTVCore

final class AppDependencies {
    let credentialStore: CredentialStore
    let mediaProvider: MediaProvider
    let modelContainer: ModelContainer

    init() {
        credentialStore = KeychainCredentialStore()
        mediaProvider = XtreamProvider()
        if let container = try? ModelContainer(for: ProviderAccount.self) {
            modelContainer = container
        } else {
            // Should be unreachable for this simple schema — last-resort fallback so
            // a rare disk/schema issue degrades to a working, if non-persistent, app
            // rather than a hard crash at launch.
            modelContainer = try! ModelContainer(
                for: ProviderAccount.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
    }
}

private struct AppDependenciesKey: EnvironmentKey {
    static let defaultValue = AppDependencies()
}

extension EnvironmentValues {
    var appDependencies: AppDependencies {
        get { self[AppDependenciesKey.self] }
        set { self[AppDependenciesKey.self] = newValue }
    }
}
