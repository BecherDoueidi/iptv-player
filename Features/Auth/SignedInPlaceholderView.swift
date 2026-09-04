import SwiftUI
import SwiftData
import IPTVCore

/// Stands in for the real Home screen (Phase 2+). Its only job right now is proving
/// session persistence and giving a way to sign out again for repeat manual testing.
struct SignedInPlaceholderView: View {
    let account: ProviderAccount

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appDependencies) private var dependencies

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("Signed in as \(account.username)")
                    .font(.title2)
                    .bold()
                if let status = account.accountStatus {
                    Text("Status: \(status)")
                        .foregroundStyle(.secondary)
                }
                Button("Sign Out", role: .destructive, action: signOut)
                    .padding(.top)
            }
            .padding()
            .navigationTitle("Home")
        }
    }

    private func signOut() {
        try? dependencies.credentialStore.clear()
        modelContext.delete(account)
        try? modelContext.save()
    }
}
