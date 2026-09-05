import SwiftUI
import SwiftData
import IPTVCore

struct SettingsView: View {
    let account: ProviderAccount
    let dependencies: AppDependencies

    @Environment(\.modelContext) private var modelContext
    @AppStorage("autoplayNextEpisode") private var autoplayNextEpisode = false
    @AppStorage("autoDeleteWatchedDownloads") private var autoDeletePolicyRaw = AutoDeletePolicy.never.rawValue
    @AppStorage("appearance") private var appearanceRaw = AppearanceOption.system.rawValue

    @State private var showingSignOutConfirmation = false
    @State private var showingClearCacheConfirmation = false
    @State private var showingClearHistoryConfirmation = false
    @State private var showingClearFavoritesConfirmation = false
    @State private var showingResetConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Server", value: account.serverURLString)
                    LabeledContent("Username", value: account.username)
                    Button("Sign Out", role: .destructive) {
                        showingSignOutConfirmation = true
                    }
                }

                Section("Playback") {
                    Toggle("Autoplay Next Episode", isOn: $autoplayNextEpisode)
                }

                Section("Downloads") {
                    Picker("Auto-Delete Watched Downloads", selection: $autoDeletePolicyRaw) {
                        ForEach(AutoDeletePolicy.allCases) { policy in
                            Text(policy.title).tag(policy.rawValue)
                        }
                    }
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appearanceRaw) {
                        ForEach(AppearanceOption.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                }

                Section("Data") {
                    Button("Clear Cache", role: .destructive) {
                        showingClearCacheConfirmation = true
                    }
                    Button("Clear Watch History", role: .destructive) {
                        showingClearHistoryConfirmation = true
                    }
                    Button("Clear Favorites", role: .destructive) {
                        showingClearFavoritesConfirmation = true
                    }
                    Button("Reset Application", role: .destructive) {
                        showingResetConfirmation = true
                    }
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Sign out of your account?",
                isPresented: $showingSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive, action: signOut)
            }
            .confirmationDialog(
                "Clear cached movie and series metadata? Downloads and watch history are kept.",
                isPresented: $showingClearCacheConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear Cache", role: .destructive, action: clearCache)
            }
            .confirmationDialog(
                "Clear all watch history and resume positions?",
                isPresented: $showingClearHistoryConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear History", role: .destructive, action: clearHistory)
            }
            .confirmationDialog(
                "Remove all favorites?",
                isPresented: $showingClearFavoritesConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear Favorites", role: .destructive, action: clearFavorites)
            }
            .confirmationDialog(
                "Reset the app? This clears everything — catalog, downloads, history, favorites, and collections — and signs you out.",
                isPresented: $showingResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset Application", role: .destructive, action: resetApplication)
            }
        }
    }

    private func signOut() {
        try? dependencies.credentialStore.clear()
        modelContext.delete(account)
        try? modelContext.save()
    }

    private func clearCache() {
        deleteAll(Movie.self)
        deleteAll(TVSeries.self) // cascades to TVSeason/TVEpisode
        try? modelContext.save()
    }

    private func clearHistory() {
        deleteAll(WatchProgress.self)
        try? modelContext.save()
    }

    private func clearFavorites() {
        deleteAll(Favorite.self)
        try? modelContext.save()
    }

    private func resetApplication() {
        for download in (try? modelContext.fetch(FetchDescriptor<Download>())) ?? [] {
            dependencies.downloadManager.cancel(contentKey: download.contentKey)
        }
        deleteAll(Movie.self)
        deleteAll(TVSeries.self)
        deleteAll(WatchProgress.self)
        deleteAll(Favorite.self)
        deleteAll(Rating.self)
        deleteAll(MediaCollection.self)
        signOut()
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) {
        guard let items = try? modelContext.fetch(FetchDescriptor<T>()) else { return }
        for item in items { modelContext.delete(item) }
    }
}
