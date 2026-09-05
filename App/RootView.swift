import SwiftUI
import SwiftData
import IPTVCore

struct RootView: View {
    @Query private var accounts: [ProviderAccount]
    @Environment(\.appDependencies) private var dependencies
    @AppStorage("appearance") private var appearanceRaw = AppearanceOption.system.rawValue

    var body: some View {
        Group {
            if let account = accounts.first {
                TabView {
                    MoviesListView(account: account, dependencies: dependencies)
                        .tabItem { Label("Movies", systemImage: "film") }
                    SeriesListView(account: account, dependencies: dependencies)
                        .tabItem { Label("Series", systemImage: "tv") }
                    SearchView(account: account, dependencies: dependencies)
                        .tabItem { Label("Search", systemImage: "magnifyingglass") }
                    LibraryView(account: account, dependencies: dependencies)
                        .tabItem { Label("Library", systemImage: "star") }
                    DownloadsListView(dependencies: dependencies)
                        .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
                    SettingsView(account: account, dependencies: dependencies)
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                }
            } else {
                LoginView(dependencies: dependencies)
            }
        }
        .preferredColorScheme(AppearanceOption(rawValue: appearanceRaw)?.colorScheme)
    }
}

#Preview {
    RootView()
}
