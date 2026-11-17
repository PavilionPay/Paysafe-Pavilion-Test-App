import AuthenticationServices
import UIKit

enum CheckoutLaunchError: Error {
    case couldNotStart
}

/// Runs the cashier page in ASWebAuthenticationSession (Safari-backed, out-of-process) rather than an
/// embedded WKWebView, so Plaid OAuth to the bank and back works the same as in Safari.
@MainActor
final class CheckoutLauncher: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func launch(sessionId: String) async throws -> CheckoutOutcome {
        // A Universal Link callback needs an HTTPS host the app has an applinks entitlement for;
        // a local http:// server returns through the custom scheme instead.
        var httpsCallbackHost: String?
        if #available(iOS 17.4, *), AppConfig.cashierBaseURL.scheme == "https" {
            httpsCallbackHost = AppConfig.cashierBaseURL.host()
        }

        var components = URLComponents(url: AppConfig.cashierURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "sid", value: sessionId),
            URLQueryItem(name: "cb", value: httpsCallbackHost == nil ? "scheme" : "https"),
        ]
        return try await start(url: components.url!, httpsCallbackHost: httpsCallbackHost, onCancel: .cancelled)
    }

    /// Opens Paysafe's demo store in the same kind of session. Nothing redirects back, so the user
    /// ends it with Cancel; that is reported as `.demoClosed` rather than a failed payment.
    func launchDemo() async throws -> CheckoutOutcome {
        try await start(url: AppConfig.paysafeDemoURL, httpsCallbackHost: nil, onCancel: .demoClosed)
    }

    private func start(url: URL, httpsCallbackHost: String?, onCancel: CheckoutOutcome) async throws -> CheckoutOutcome {
        try await withCheckedThrowingContinuation { continuation in
            let completion: ASWebAuthenticationSession.CompletionHandler = { callbackURL, error in
                if let error {
                    #if DEBUG
                    // A missing webcredentials association also ends here as "cancelled"; the description names it.
                    print("Cashier session ended: \(error.localizedDescription)")
                    #endif
                    let code = (error as? ASWebAuthenticationSessionError)?.code
                    continuation.resume(returning: code == .canceledLogin ? onCancel : .failed(error.localizedDescription))
                } else if let callbackURL {
                    continuation.resume(returning: Self.parse(callbackURL))
                } else {
                    continuation.resume(returning: .failed("No callback URL"))
                }
            }

            let session: ASWebAuthenticationSession
            if #available(iOS 17.4, *), let httpsCallbackHost {
                session = ASWebAuthenticationSession(
                    url: url,
                    callback: .https(host: httpsCallbackHost, path: AppConfig.returnPath),
                    completionHandler: completion)
            } else {
                session = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: AppConfig.fallbackScheme,
                    completionHandler: completion)
            }
            session.presentationContextProvider = self
            // Private by default; see AppConfig.privateCashierSession for the trade-off.
            session.prefersEphemeralWebBrowserSession = AppConfig.privateCashierSession
            self.session = session

            if !session.start() {
                continuation.resume(throwing: CheckoutLaunchError.couldNotStart)
            }
        }
    }

    /// Parses `.../cashier-return?status=success|cancelled|failed&ref=...`.
    nonisolated static func parse(_ url: URL) -> CheckoutOutcome {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        // cashier.html builds the query with URLSearchParams, which encodes spaces as "+".
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value?.replacingOccurrences(of: "+", with: " ")
        }
        switch value("status") {
        case "success": return .success(reference: value("ref"))
        case "cancelled": return .cancelled
        default: return .failed(value("message") ?? "Payment did not complete")
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
