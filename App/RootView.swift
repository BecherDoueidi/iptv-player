import SwiftUI
import SwiftData
import IPTVCore

struct RootView: View {
    @Query private var accounts: [ProviderAccount]
    @Environment(\.appDependencies) private var dependencies

    var body: some View {
        if let account = accounts.first {
            MoviesListView(account: account, dependencies: dependencies)
        } else {
            LoginView(dependencies: dependencies)
        }
    }
}

#Preview {
    RootView()
}
