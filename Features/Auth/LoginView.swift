import SwiftUI

struct LoginView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: AuthViewModel

    init(dependencies: AppDependencies) {
        _viewModel = State(initialValue: AuthViewModel(dependencies: dependencies))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Server address (e.g. http://host:port)", text: $viewModel.serverURLText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                Section("Account") {
                    TextField("Username", text: $viewModel.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $viewModel.password)
                }

                if case .failed(let message) = viewModel.state {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await viewModel.signIn(modelContext: modelContext) }
                    } label: {
                        HStack {
                            Spacer()
                            if viewModel.state == .authenticating {
                                ProgressView()
                            } else {
                                Text("Sign In")
                            }
                            Spacer()
                        }
                    }
                    .disabled(!viewModel.canSubmit)
                }
            }
            .navigationTitle("IPTV Player")
        }
    }
}
