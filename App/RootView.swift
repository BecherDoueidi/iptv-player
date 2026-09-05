import SwiftUI
import SwiftData
import IPTVCore

struct RootView: View {
    @Query private var accounts: [ProviderAccount]
    @Environment(\.appDependencies) private var dependencies

    var body: some View {
        if let account = accounts.first {
            TabView {
                MoviesListView(account: account, dependencies: dependencies)
                    .tabItem { Label("Movies", systemImage: "film") }
                SeriesListView(account: account, dependencies: dependencies)
                    .tabItem { Label("Series", systemImage: "tv") }
                DownloadsListView(dependencies: dependencies)
                    .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
            }
        } else {
            LoginView(dependencies: dependencies)
        }
    }
}

#Preview {
    RootView()
}
