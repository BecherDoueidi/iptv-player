import Foundation
import Observation
import SwiftData
import IPTVCore

enum AuthState: Equatable {
    case idle
    case authenticating
    case failed(String)
}

@Observable
final class AuthViewModel {
    var serverURLText: String = ""
    var username: String = ""
    var password: String = ""
    private(set) var state: AuthState = .idle

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    var canSubmit: Bool {
        !serverURLText.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && state != .authenticating
    }

    @MainActor
    func signIn(modelContext: ModelContext) async {
        guard let serverURL = Self.normalizedURL(from: serverURLText) else {
            state = .failed("Enter a valid server address, e.g. http://example.com:8080")
            return
        }

        state = .authenticating
        let credentials = XtreamCredentials(serverURL: serverURL, username: username, password: password)

        do {
            let accountInfo = try await dependencies.mediaProvider.authenticate(credentials: credentials)
            guard accountInfo.isAuthenticated else {
                state = .failed(accountInfo.message ?? "Invalid username or password.")
                return
            }

            try dependencies.credentialStore.save(credentials)

            let account = ProviderAccount(
                sourceID: SourceID.make(serverURL: serverURL, username: username),
                serverURLString: serverURL.absoluteString,
                username: username,
                accountStatus: accountInfo.status,
                isTrial: accountInfo.isTrial,
                expiresAt: accountInfo.expiresAt,
                lastSuccessfulSyncAt: .now
            )
            modelContext.insert(account)
            try modelContext.save()
            state = .idle
        } catch {
            state = .failed(Self.errorMessage(for: error))
        }
    }

    private static func normalizedURL(from text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains("://") {
            trimmed = "http://" + trimmed
        }
        guard let url = URL(string: trimmed), url.host != nil else { return nil }
        return url
    }

    private static func errorMessage(for error: Error) -> String {
        switch error {
        case let apiError as XtreamAPIError:
            switch apiError {
            case .invalidServerURL:
                return "That server address doesn't look right."
            case .network(let message):
                return "Couldn't reach the server: \(message)"
            case .unexpectedResponse:
                return "The server sent back something unexpected."
            case .httpStatus(let code):
                return "Server returned an error (HTTP \(code))."
            }
        default:
            return "Something went wrong: \(error.localizedDescription)"
        }
    }
}
