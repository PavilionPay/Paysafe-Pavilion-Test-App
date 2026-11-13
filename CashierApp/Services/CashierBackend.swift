import Foundation

/// Your operator backend. It owns the Paysafe private key and never exposes it to the app.
protocol CashierBackend {
    /// Creates a server-side cashier session and returns an opaque, short-lived session id.
    /// The cashier page exchanges it for the Checkout config (public key, amount, consumerId).
    /// Sensitive values must not travel in the URL. `patron` overrides the server's default TEST patron.
    func createCashierSession(amount: Decimal, patron: Patron?) async throws -> String

    func fetchBalance() async throws -> Decimal
}

struct CashierBackendError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Talks to server/server.py.
struct HTTPCashierBackend: CashierBackend {
    var baseURL: URL = AppConfig.cashierBaseURL

    func createCashierSession(amount: Decimal, patron: Patron?) async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "/api/cashier/session"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = ["amount": NSDecimalNumber(decimal: amount).doubleValue]
        if let patron { payload["patron"] = patron.payload }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let body = try await send(request)
        guard let sid = body["sid"] as? String else { throw CashierBackendError(message: "No session id") }
        return sid
    }

    func fetchBalance() async throws -> Decimal {
        let body = try await send(URLRequest(url: baseURL.appending(path: "/api/balance")))
        guard let value = body["balance"] as? NSNumber else { throw CashierBackendError(message: "No balance") }
        return value.decimalValue
    }

    private func send(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CashierBackendError(message: body["message"] as? String ?? "Cashier server error")
        }
        return body
    }
}

/// Stand-in for SwiftUI previews and offline UI work.
struct MockCashierBackend: CashierBackend {
    func createCashierSession(amount: Decimal, patron: Patron?) async throws -> String { "demo" }
    func fetchBalance() async throws -> Decimal { 4_500 }
}
